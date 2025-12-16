import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import { join } from 'path';
import { existsSync } from 'fs';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const configService = app.get(ConfigService);
  
  // Serve static files from client build in production
  const isProduction = process.env.NODE_ENV === 'production';
  if (isProduction) {
    // Path relative to compiled dist folder (which is at root level)
    const clientBuildPath = join(__dirname, '../../client/dist');
    
    if (existsSync(clientBuildPath)) {
      app.useStaticAssets(clientBuildPath, {
        prefix: '/',
      });
      
      // Serve index.html for all non-API routes (SPA routing)
      app.getHttpAdapter().get('*', (req, res, next) => {
        // Don't serve index.html for API routes
        //@ts-ignore
        if (req.path.startsWith('/api') || req.path.startsWith('/health')) {
          return next();
        }
        //@ts-ignore
        res.sendFile(join(clientBuildPath, 'index.html'));
      });
      
      console.log(`Serving client from: ${clientBuildPath}`);
    } else {
      console.warn(`Client build not found at: ${clientBuildPath}`);
    }
  }
  
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
  if (!isProduction) {
    console.log(`CORS enabled for client: ${clientUrl}`);
  }
}
bootstrap();

