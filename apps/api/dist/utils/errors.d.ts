export declare class AppError extends Error {
    message: string;
    statusCode: number;
    code?: string | undefined;
    constructor(message: string, statusCode?: number, code?: string | undefined);
}
export declare class ValidationError extends AppError {
    details?: any | undefined;
    constructor(message: string, details?: any | undefined);
}
//# sourceMappingURL=errors.d.ts.map