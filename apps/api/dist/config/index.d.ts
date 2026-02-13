import type { SignOptions } from 'jsonwebtoken';
export declare const config: {
    env: string;
    port: number;
    database: {
        url: string;
        host: string;
        port: number;
        name: string;
        user: string;
        password: string;
        ssl: boolean;
    };
    jwt: {
        readonly secret: string;
        expiresIn: SignOptions["expiresIn"];
        readonly refreshSecret: string;
        refreshExpiresIn: SignOptions["expiresIn"];
    };
    redis: {
        url: string;
        password: string | undefined;
    };
    minio: {
        endpoint: string;
        port: number;
        useSSL: boolean;
        accessKey: string;
        secretKey: string;
        bucket: string;
    };
    stripe: {
        secretKey: string;
        webhookSecret: string;
        premiumPriceId: string;
    };
    sendgrid: {
        apiKey: string;
        fromEmail: string;
        replyToEmail: string;
    };
    google: {
        clientId: string;
    };
    apple: {
        bundleId: string;
    };
    openai: {
        apiKey: string;
    };
    revenuecat: {
        readonly apiKey: string;
        readonly webhookSecret: string;
    };
    app: {
        baseUrl: string;
        frontendUrl: string;
        dashboardUrl: string;
        apiUrl: string;
    };
    cors: {
        origins: string[];
    };
    rateLimit: {
        windowMs: number;
        max: number;
    };
};
//# sourceMappingURL=index.d.ts.map