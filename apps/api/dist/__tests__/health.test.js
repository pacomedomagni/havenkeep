"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
const app = (0, helpers_1.getTestApp)();
describe('Health endpoint', () => {
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    describe('GET /health', () => {
        it('should return 200 with status ok', async () => {
            const res = await (0, supertest_1.default)(app).get('/health');
            expect(res.status).toBe(200);
            expect(res.body.status).toBe('ok');
            expect(res.body).toHaveProperty('timestamp');
            expect(res.body).toHaveProperty('uptime');
            expect(res.body).toHaveProperty('environment');
        });
    });
});
//# sourceMappingURL=health.test.js.map