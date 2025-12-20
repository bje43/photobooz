import {
  Controller,
  Get,
  Post,
  Put,
  Body,
  Param,
  UseGuards,
} from '@nestjs/common';
import { BoothsService } from './booths.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('booths')
@UseGuards(JwtAuthGuard)
export class BoothsController {
  constructor(private readonly boothsService: BoothsService) {}

  @Get()
  findAll() {
    return this.boothsService.findAll();
  }

  @Post()
  create(@Body() createDto: { boothId: string; name?: string }) {
    return this.boothsService.create(createDto.boothId, createDto.name);
  }

  @Put(':id')
  update(@Param('id') id: string, @Body() updateDto: { name: string }) {
    return this.boothsService.update(id, updateDto.name);
  }

  @Put(':id/operating-hours')
  updateOperatingHours(
    @Param('id') id: string,
    @Body() updateDto: { operatingHours: any },
  ) {
    return this.boothsService.updateOperatingHours(
      id,
      updateDto.operatingHours,
    );
  }
}

