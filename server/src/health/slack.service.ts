import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { WebClient } from '@slack/web-api';
import { Photobooth, HealthLog } from '@prisma/client';

@Injectable()
export class SlackService {
  private readonly logger = new Logger(SlackService.name);
  private readonly client: WebClient | null;
  private readonly channel: string;

  constructor(private readonly configService: ConfigService) {
    const token = this.configService.get<string>('SLACK_BOT_TOKEN');
    const channel = "health-alerts";
    this.client = token ? new WebClient(token) : null;
    this.channel = channel;
  }

  async sendHealthUpdate(photobooth: Photobooth, healthLog: HealthLog) {
    if (!this.client) {
      this.logger.warn('SLACK_BOT_TOKEN not configured, skipping Slack notification');
      return;
    }

    try {
      const metadata = healthLog.metadata
        ? JSON.parse(healthLog.metadata)
        : null;

      const blocks: any[] = [
        {
          type: 'header',
          text: {
            type: 'plain_text',
            text: '📸 Photobooth Health Update',
            emoji: true,
          },
        },
        {
          type: 'section',
          fields: [
            {
              type: 'mrkdwn',
              text: `*Booth ID:*\n${photobooth.boothId}`,
            },
            {
              type: 'mrkdwn',
              text: `*Name:*\n${photobooth.name || 'N/A'}`,
            },
            {
              type: 'mrkdwn',
              text: `*Status:*\n${healthLog.status}`,
            },
            {
              type: 'mrkdwn',
              text: `*Time:*\n${new Date(healthLog.createdAt).toLocaleString()}`,
            },
          ],
        },
      ];

      if (healthLog.message) {
        blocks.push({
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*Message:*\n${healthLog.message}`,
          },
        });
      }

      await this.client.chat.postMessage({
        channel: this.channel,
        text: `📸 Photobooth Health Update`,
        blocks,
      });
      this.logger.log(`Slack notification sent for booth ${photobooth.boothId}`);
    } catch (error) {
      this.logger.error('Error sending Slack notification', error);
    }
  }

  async sendStaleAlert(photobooth: Photobooth, minutesSinceLastPing: number) {
    if (!this.client) {
      this.logger.warn('SLACK_BOT_TOKEN not configured, skipping Slack notification');
      return;
    }

    try {
      await this.client.chat.postMessage({
        channel: this.channel,
        text: `⚠️ Photobooth Stale Alert`,
        blocks: [
          {
            type: 'header',
            text: {
              type: 'plain_text',
              text: '⚠️ Photobooth Stale Alert',
              emoji: true,
            },
          },
          {
            type: 'section',
            fields: [
              {
                type: 'mrkdwn',
                text: `*Name:*\n${photobooth.name || 'N/A'}`,
              },
              {
                type: 'mrkdwn',
                text: `*Booth ID:*\n${photobooth.boothId}`,
              },
              {
                type: 'mrkdwn',
                text: `*Last Ping:*\n${photobooth.lastPing.toLocaleString()}`,
              },
              {
                type: 'mrkdwn',
                text: `*Minutes Since Last Ping:*\n${minutesSinceLastPing}`,
              },
            ],
          },
        ],
      });
      this.logger.log(
        `Stale alert sent for booth ${photobooth.boothId} (${minutesSinceLastPing} minutes)`,
      );
    } catch (error) {
      this.logger.error('Error sending stale alert to Slack', error);
    }
  }

  async sendNonNormalModeAlert(
    photobooth: Photobooth,
    mode: string,
    hoursInMode: number,
  ) {
    if (!this.client) {
      this.logger.warn('SLACK_BOT_TOKEN not configured, skipping Slack notification');
      return;
    }

    try {
      await this.client.chat.postMessage({
        channel: this.channel,
        text: `⚠️ Photobooth Non-Normal Mode Alert`,
        blocks: [
          {
            type: 'header',
            text: {
              type: 'plain_text',
              text: '⚠️ Photobooth Non-Normal Mode Alert',
              emoji: true,
            },
          },
          {
            type: 'section',
            fields: [
              {
                type: 'mrkdwn',
                text: `*Booth ID:*\n${photobooth.boothId}`,
              },
              {
                type: 'mrkdwn',
                text: `*Name:*\n${photobooth.name || 'N/A'}`,
              },
              {
                type: 'mrkdwn',
                text: `*Current Mode:*\n${mode}`,
              },
              {
                type: 'mrkdwn',
                text: `*Hours in Mode:*\n${hoursInMode.toFixed(1)}`,
              },
            ],
          },
          {
            type: 'section',
            text: {
              type: 'mrkdwn',
              text: `This booth has been in *${mode}* mode for more than 24 hours. Please check if this is expected.`,
            },
          },
        ],
      });
      this.logger.log(
        `Non-normal mode alert sent for booth ${photobooth.boothId} (${mode} mode for ${hoursInMode.toFixed(1)} hours)`,
      );
    } catch (error) {
      this.logger.error('Error sending non-normal mode alert to Slack', error);
    }
  }
}

