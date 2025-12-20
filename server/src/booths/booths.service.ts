import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';

export interface OperatingHours {
  enabled: boolean;
  schedule: Array<{
    day: number; // 0 = Sunday, 1 = Monday, etc.
    start: string; // "HH:mm" format
    end: string; // "HH:mm" format
  }>;
}

@Injectable()
export class BoothsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

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

      // Check if current day/time is within any schedule
      for (const schedule of hours.schedule) {
        if (schedule.day === currentDay) {
          if (currentTime >= schedule.start && currentTime <= schedule.end) {
            return true;
          }
        }
      }

      return false; // Not within any operating hours
    } catch {
      return true; // Invalid schedule = assume always on
    }
  }

  async findAll() {
    const staleThresholdMinutes =
      parseInt(
        this.configService.get<string>('STALE_THRESHOLD_MINUTES', '15'),
      ) || 15;

    const thresholdDate = new Date();
    thresholdDate.setMinutes(
      thresholdDate.getMinutes() - staleThresholdMinutes,
    );

    const booths = await this.prisma.photobooth.findMany({
      orderBy: { lastPing: 'desc' },
      include: {
        healthLogs: {
          orderBy: { createdAt: 'desc' },
          take: 1,
        },
      },
    });

    return booths.map((booth) => {
      const lastLog = booth.healthLogs[0];
      const minutesSinceLastPing = Math.floor(
        (new Date().getTime() - booth.lastPing.getTime()) / 60000,
      );
      const isStale = booth.lastPing < thresholdDate;
      const isWithinHours = this.isWithinOperatingHours(
        booth.operatingHours,
        booth.timezone,
      );

      let mode = 'Unknown';
      if (lastLog?.metadata) {
        try {
          const metadata = JSON.parse(lastLog.metadata);
          mode = metadata.mode || 'Unknown';
        } catch {}
      }

      let status = lastLog?.status || 'unknown';
      
      // If outside operating hours, mark as offline (expected)
      if (mode === 'Maintenance') {
        status = 'maintenance';
      } else if (!isWithinHours) {
        status = 'offline';
      } else if (isStale) {
        // If within hours but stale, that's a problem
        status = 'stale';
      }

      

      let operatingHours: OperatingHours | null = null;
      if (booth.operatingHours) {
        try {
          operatingHours = JSON.parse(booth.operatingHours);
        } catch {}
      }

      return {
        id: booth.id,
        boothId: booth.boothId,
        name: booth.name,
        status,
        mode,
        timezone: booth.timezone,
        operatingHours: operatingHours || { enabled: false, schedule: [] },
        lastPing: booth.lastPing,
        minutesSinceLastPing,
        isMaintenance: mode === 'Maintenance',
        isWithinOperatingHours: isWithinHours,
        message: lastLog?.message,
      };
    });
  }

  async create(boothId: string, name?: string) {
    return this.prisma.photobooth.create({
      data: {
        boothId,
        name,
      },
    });
  }

  async update(id: string, name: string) {
    const booth = await this.prisma.photobooth.findUnique({
      where: { id },
    });

    if (!booth) {
      throw new NotFoundException('Booth not found');
    }

    return this.prisma.photobooth.update({
      where: { id },
      data: { name },
    });
  }

  async updateOperatingHours(
    id: string,
    operatingHours: OperatingHours,
  ) {
    const booth = await this.prisma.photobooth.findUnique({
      where: { id },
    });

    if (!booth) {
      throw new NotFoundException('Booth not found');
    }

    return this.prisma.photobooth.update({
      where: { id },
      data: {
        operatingHours: JSON.stringify(operatingHours),
      },
    });
  }
}

