import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { SlackService } from './slack.service';
import { Cron, CronExpression } from '@nestjs/schedule';
import { OperatingHours } from '../booths/booths.service';

interface HealthPingDto {
  boothId: string;
  name?: string;
  status: string;
  message?: string;
  metadata?: Record<string, any>;
}

@Injectable()
export class HealthService {
  private readonly logger = new Logger(HealthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
    private readonly slackService: SlackService,
  ) {}

  async processHealthPing(healthData: HealthPingDto) {
    try {
      // Extract timezone from metadata if provided
      const timezone = healthData.metadata?.timezone || null;

      // Upsert photobooth
      const photobooth = await this.prisma.photobooth.upsert({
        where: { boothId: healthData.boothId },
        update: {
          timezone: timezone || undefined,
          lastPing: new Date(),
          updatedAt: new Date(),
        },
        create: {
          boothId: healthData.boothId,
          name: healthData.name,
          timezone: timezone || null,
          lastPing: new Date(),
        },
      });

      // Create health log
      const healthLog = await this.prisma.healthLog.create({
        data: {
          photoboothId: photobooth.id,
          status: healthData.status,
          message: healthData.message,
          metadata: healthData.metadata
            ? JSON.stringify(healthData.metadata)
            : null,
        },
      });

      this.logger.log(
        `Health ping received from booth ${healthData.boothId}: ${healthData.status}`,
      );

      // Send Slack alert if there are issues (error or warning status)
      if (healthData.status === 'error' || healthData.status === 'warning') {
        await this.slackService.sendHealthUpdate(photobooth, healthLog);
      }

      return {
        success: true,
        message: 'Health ping processed',
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      this.logger.error('Error processing health ping', error);
      throw error;
    }
  }

  private isWithinOperatingHours(
    operatingHours: string | null,
    timezone: string | null,
  ): boolean {
    if (!operatingHours) {
      return true; // Default: always on
    }

    try {
      const hours: OperatingHours = JSON.parse(operatingHours);
      if (!hours.enabled || !hours.schedule || hours.schedule.length === 0) {
        return true; // No schedule = always on
      }

      // Get current time in booth's timezone
      const tz = timezone || 'UTC';
      const now = new Date();
      
      // Get day of week in booth's timezone
      const dayFormatter = new Intl.DateTimeFormat('en-US', {
        timeZone: tz,
        weekday: 'short',
      });
      const dayStr = dayFormatter.format(now);
      const dayMap: Record<string, number> = {
        'Sun': 0, 'Mon': 1, 'Tue': 2, 'Wed': 3, 'Thu': 4, 'Fri': 5, 'Sat': 6
      };
      const currentDay = dayMap[dayStr] ?? 0;
      
      // Get time in booth's timezone
      const timeFormatter = new Intl.DateTimeFormat('en-US', {
        timeZone: tz,
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
      });
      const timeParts = timeFormatter.formatToParts(now);
      const hour = timeParts.find(p => p.type === 'hour')?.value || '00';
      const minute = timeParts.find(p => p.type === 'minute')?.value || '00';
      const currentTime = `${hour.padStart(2, '0')}:${minute.padStart(2, '0')}`;

      // Check if current time is within any schedule entry for today
      for (const entry of hours.schedule) {
        if (entry.day === currentDay) {
          if (currentTime >= entry.start && currentTime <= entry.end) {
            return true;
          }
        }
      }

      return false; // Not within any operating hours
    } catch {
      return true; // Invalid schedule = assume always on
    }
  }

  @Cron(CronExpression.EVERY_5_MINUTES)
  async checkStaleBooths() {
    const staleThresholdMinutes = 30;
    const thresholdDate = new Date();
    thresholdDate.setMinutes(
      thresholdDate.getMinutes() - staleThresholdMinutes,
    );

    try {
      const booths = await this.prisma.photobooth.findMany({
        where: {
          lastPing: {
            lt: thresholdDate,
          },
        },
      });

      for (const booth of booths) {
        // Check if booth is within operating hours
        const isWithinHours = this.isWithinOperatingHours(
          booth.operatingHours,
          booth.timezone,
        );

        // Only send alert if within operating hours
        if (isWithinHours) {
          const minutesSinceLastPing = Math.floor(
            (new Date().getTime() - booth.lastPing.getTime()) / 60000,
          );
          await this.slackService.sendStaleAlert(booth, minutesSinceLastPing);
          this.logger.warn(
            `Stale booth detected: ${booth.boothId} (${minutesSinceLastPing} minutes since last ping)`,
          );
        }
      }
    } catch (error) {
      this.logger.error('Error checking stale booths', error);
    }
  }

  @Cron(CronExpression.EVERY_DAY_AT_2AM)
  async cleanupOldHealthLogs() {
    const retentionDays = 3;
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - retentionDays);

    try {
      const result = await this.prisma.healthLog.deleteMany({
        where: {
          createdAt: {
            lt: cutoffDate,
          },
        },
      });

      if (result.count > 0) {
        this.logger.log(
          `Cleaned up ${result.count} health log(s) older than ${retentionDays} days`,
        );
      }
    } catch (error) {
      this.logger.error('Error cleaning up old health logs', error);
    }
  }
}

