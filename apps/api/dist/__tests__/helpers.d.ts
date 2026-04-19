export declare function getTestApp(): import("express-serve-static-core").Express;
export declare function getAuthToken(userId: string, extra?: Record<string, any>): string;
export declare function getAdminToken(userId: string): string;
export declare function createTestUser(overrides?: Record<string, any>): Promise<{
    user: any;
    token: string;
}>;
export declare function createTestHome(userId: string, overrides?: Record<string, any>): Promise<any>;
export declare function createTestItem(userId: string, homeId: string, overrides?: Record<string, any>): Promise<any>;
//# sourceMappingURL=helpers.d.ts.map