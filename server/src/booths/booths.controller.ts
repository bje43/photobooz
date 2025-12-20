import {
  Controller,
  Get,
  Post,
  Put,
  Body,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import { BoothsService } from './booths.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('booths')
@UseGuards(JwtAuthGuard)
export class BoothsController {
  constructor(private readonly boothsService: BoothsService) {}

  @Get()
  findAll(@Query('groupBy') groupBy?: 'geographicArea' | 'assignedTech' | 'both') {
    if (groupBy) {
      return this.boothsService.findAllGrouped(groupBy);
    }
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

  @Put(':id/geographic-area')
  updateGeographicArea(
    @Param('id') id: string,
    @Body() updateDto: { geographicArea: string | null },
  ) {
    return this.boothsService.updateGeographicArea(id, updateDto.geographicArea);
  }

  @Put(':id/assigned-tech')
  updateAssignedTech(
    @Param('id') id: string,
    @Body() updateDto: { assignedTech: string | null },
  ) {
    return this.boothsService.updateAssignedTech(id, updateDto.assignedTech);
  }
}

