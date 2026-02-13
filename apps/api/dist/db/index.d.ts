import { Pool, QueryResult, QueryResultRow } from 'pg';
export declare const pool: Pool;
export declare function query<T extends QueryResultRow = any>(text: string, params?: any[]): Promise<QueryResult<T>>;
export declare function getClient(): Promise<import("pg").PoolClient>;
//# sourceMappingURL=index.d.ts.map