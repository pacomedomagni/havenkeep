import express from 'express';
export interface CreateAppOptions {
    rateLimiter?: express.RequestHandler;
}
export declare function createApp(options?: CreateAppOptions): import("express-serve-static-core").Express;
//# sourceMappingURL=app.d.ts.map