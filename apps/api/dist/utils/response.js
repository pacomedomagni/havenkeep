"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendSuccess = sendSuccess;
exports.sendMessage = sendMessage;
function sendSuccess(res, data, options) {
    const body = { success: true, data };
    if (options?.pagination)
        body.pagination = options.pagination;
    if (options?.message)
        body.message = options.message;
    res.status(options?.status ?? 200).json(body);
}
function sendMessage(res, message, status = 200) {
    res.status(status).json({ success: true, message });
}
//# sourceMappingURL=response.js.map