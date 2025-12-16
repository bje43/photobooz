import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);
  
  // Configure CORS for React client and photobooth clients
  const clientUrl = configService.get<string>('CLIENT_URL') || 'http://localhost:5173';
  app.enableCors({
    origin: [
      clientUrl,
      'http://localhost:3000',
      'http://localhost:5173',
      'http://localhost:5174',
    ],
    credentials: true,
  });
  
  const port = process.env.PORT || 3000;
  await app.listen(port);
  console.log(`Application is running on: ${port}`);
  console.log(`CORS enabled for client: ${clientUrl}`);
}
bootstrap();

