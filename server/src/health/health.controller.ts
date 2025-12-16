import {
  Controller,
  Post,
  Body,
  Headers,
  UnauthorizedException,
  BadRequestException,
} from '@nestjs/common';
import { HealthService } from './health.service';
import { ConfigService } from '@nestjs/config';

interface HealthPingDto {
  boothId: string;
  name?: string;
  status: string;
  message?: string;
  metadata?: Record<string, any>;
}

@Controller('health')
export class HealthController {
  constructor(
    private readonly healthService: HealthService,
    private readonly configService: ConfigService,
  ) {}

  @Post('ping')
  async ping(
    @Body() healthData: HealthPingDto,
    @Headers('x-api-key') apiKey: string,
  ) {
    // Validate API key
    const validApiKey = this.configService.get<string>('API_KEY');
    if (!validApiKey) {
      throw new BadRequestException('API_KEY not configured');
    }

    if (!apiKey || apiKey !== validApiKey) {
      throw new UnauthorizedException('Invalid API key');
    }

    // Validate required fields
    if (!healthData.boothId || !healthData.status) {
      throw new BadRequestException('boothId and status are required');
    }

    return this.healthService.processHealthPing(healthData);
  }
}

