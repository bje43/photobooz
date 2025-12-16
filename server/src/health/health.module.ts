import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';
import { SlackService } from './slack.service';

@Module({
  controllers: [HealthController],
  providers: [HealthService, SlackService],
})
export class HealthModule {}

