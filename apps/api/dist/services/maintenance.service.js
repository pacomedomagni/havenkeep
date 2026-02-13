"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MaintenanceService = void 0;
const db_1 = require("../db");
const logger_1 = require("../utils/logger");
const errors_1 = require("../utils/errors");
class MaintenanceService {
    /**
     * Get maintenance schedules for a given item category
     */
    static async getSchedulesByCategory(category) {
        try {
            const result = await db_1.pool.query(`SELECT *
         FROM maintenance_schedules
         WHERE category = $1
         ORDER BY priority ASC, task_name ASC`, [category]);
            return result.rows;
        }
        catch (error) {
            logger_1.logger.error({ error, category }, 'Error fetching maintenance schedules');
            throw error;
        }
    }
    /**
     * Get due/overdue maintenance tasks for a specific item
     * Compares schedules for the item's category against maintenance history
     */
    static async getItemMaintenanceDue(userId, itemId) {
        try {
            // Verify item belongs to user and get item details
            const itemResult = await db_1.pool.query(`SELECT id, name, category, purchase_date, installation_date
         FROM items
         WHERE id = $1 AND user_id = $2`, [itemId, userId]);
            if (itemResult.rows.length === 0) {
                throw new errors_1.AppError('Item not found or does not belong to user', 404);
            }
            const item = itemResult.rows[0];
            // Get all schedules for this item's category
            const schedulesResult = await db_1.pool.query(`SELECT *
         FROM maintenance_schedules
         WHERE category = $1
         ORDER BY priority ASC, task_name ASC`, [item.category]);
            // Get the most recent maintenance history for each schedule on this item
            const historyResult = await db_1.pool.query(`SELECT DISTINCT ON (schedule_id)
           schedule_id,
           completed_date
         FROM maintenance_history
         WHERE item_id = $1 AND user_id = $2 AND schedule_id IS NOT NULL
         ORDER BY schedule_id, completed_date DESC`, [itemId, userId]);
            // Build a map of schedule_id -> last completed date
            const historyMap = new Map();
            for (const row of historyResult.rows) {
                historyMap.set(row.schedule_id, row.completed_date);
            }
            const now = new Date();
            const itemStartDate = item.installation_date || item.purchase_date || item.created_at;
            const tasks = schedulesResult.rows.map((schedule) => {
                const lastCompleted = historyMap.get(schedule.id) || null;
                // Calculate next due date: from last completion, or from item start date
                const baseDate = lastCompleted ? new Date(lastCompleted) : new Date(itemStartDate);
                const nextDue = new Date(baseDate);
                nextDue.setMonth(nextDue.getMonth() + schedule.frequency_months);
                const diffMs = nextDue.getTime() - now.getTime();
                const daysUntilDue = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
                return {
                    schedule,
                    last_completed: lastCompleted,
                    next_due: nextDue,
                    is_overdue: daysUntilDue < 0,
                    days_until_due: daysUntilDue,
                };
            });
            // Sort: overdue first (most overdue), then by soonest due
            tasks.sort((a, b) => a.days_until_due - b.days_until_due);
            return {
                item: { id: item.id, name: item.name, category: item.category },
                tasks,
            };
        }
        catch (error) {
            logger_1.logger.error({ error, userId, itemId }, 'Error fetching item maintenance due');
            throw error;
        }
    }
    /**
     * Get all due maintenance across all user items
     */
    static async getUserMaintenanceSummary(userId) {
        try {
            // Get all non-archived items for the user
            const itemsResult = await db_1.pool.query(`SELECT id, name, category, purchase_date, installation_date, created_at
         FROM items
         WHERE user_id = $1 AND is_archived = FALSE
         ORDER BY name ASC`, [userId]);
            if (itemsResult.rows.length === 0) {
                return { total_due: 0, total_overdue: 0, items: [] };
            }
            // Get all unique categories from user's items
            const categories = [...new Set(itemsResult.rows.map((i) => i.category))];
            // Get all schedules for those categories
            const schedulesResult = await db_1.pool.query(`SELECT *
         FROM maintenance_schedules
         WHERE category = ANY($1)
         ORDER BY priority ASC`, [categories]);
            // Build a map of category -> schedules
            const schedulesByCategory = new Map();
            for (const schedule of schedulesResult.rows) {
                const list = schedulesByCategory.get(schedule.category) || [];
                list.push(schedule);
                schedulesByCategory.set(schedule.category, list);
            }
            // Get all maintenance history for the user's items
            const itemIds = itemsResult.rows.map((i) => i.id);
            const historyResult = await db_1.pool.query(`SELECT DISTINCT ON (item_id, schedule_id)
           item_id,
           schedule_id,
           completed_date
         FROM maintenance_history
         WHERE item_id = ANY($1) AND user_id = $2 AND schedule_id IS NOT NULL
         ORDER BY item_id, schedule_id, completed_date DESC`, [itemIds, userId]);
            // Build a map of "itemId:scheduleId" -> last completed date
            const historyMap = new Map();
            for (const row of historyResult.rows) {
                historyMap.set(`${row.item_id}:${row.schedule_id}`, row.completed_date);
            }
            const now = new Date();
            let totalDue = 0;
            let totalOverdue = 0;
            const items = itemsResult.rows
                .map((item) => {
                const schedules = schedulesByCategory.get(item.category) || [];
                const itemStartDate = item.installation_date || item.purchase_date || item.created_at;
                const tasks = schedules.map((schedule) => {
                    const lastCompleted = historyMap.get(`${item.id}:${schedule.id}`) || null;
                    const baseDate = lastCompleted ? new Date(lastCompleted) : new Date(itemStartDate);
                    const nextDue = new Date(baseDate);
                    nextDue.setMonth(nextDue.getMonth() + schedule.frequency_months);
                    const diffMs = nextDue.getTime() - now.getTime();
                    const daysUntilDue = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
                    return {
                        schedule_id: schedule.id,
                        task_name: schedule.task_name,
                        next_due: nextDue,
                        is_overdue: daysUntilDue < 0,
                        days_until_due: daysUntilDue,
                        priority: schedule.priority,
                    };
                });
                // Only include tasks that are due within 30 days or overdue
                const dueTasks = tasks.filter((t) => t.days_until_due <= 30);
                dueTasks.sort((a, b) => a.days_until_due - b.days_until_due);
                const dueCount = dueTasks.length;
                const overdueCount = dueTasks.filter((t) => t.is_overdue).length;
                totalDue += dueCount;
                totalOverdue += overdueCount;
                return {
                    item_id: item.id,
                    item_name: item.name,
                    category: item.category,
                    due_count: dueCount,
                    overdue_count: overdueCount,
                    tasks: dueTasks,
                };
            })
                .filter((item) => item.tasks.length > 0);
            // Sort items by most overdue tasks first
            items.sort((a, b) => b.overdue_count - a.overdue_count);
            return {
                total_due: totalDue,
                total_overdue: totalOverdue,
                items,
            };
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error fetching user maintenance summary');
            throw error;
        }
    }
    /**
     * Log a completed maintenance task
     */
    static async logMaintenance(userId, data) {
        const client = await db_1.pool.connect();
        try {
            await client.query('BEGIN');
            // Verify item belongs to user
            const itemCheck = await client.query('SELECT id FROM items WHERE id = $1 AND user_id = $2', [data.item_id, userId]);
            if (itemCheck.rows.length === 0) {
                throw new errors_1.AppError('Item not found or does not belong to user', 404);
            }
            // If schedule_id is provided, verify it exists
            if (data.schedule_id) {
                const scheduleCheck = await client.query('SELECT id FROM maintenance_schedules WHERE id = $1', [data.schedule_id]);
                if (scheduleCheck.rows.length === 0) {
                    throw new errors_1.AppError('Maintenance schedule not found', 404);
                }
            }
            // Insert maintenance history record
            const result = await client.query(`INSERT INTO maintenance_history (
          item_id, user_id, schedule_id, task_name,
          completed_date, notes, duration_minutes, cost
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *`, [
                data.item_id,
                userId,
                data.schedule_id || null,
                data.task_name,
                data.completed_date || new Date(),
                data.notes || null,
                data.duration_minutes || null,
                data.cost || 0,
            ]);
            const entry = result.rows[0];
            // Update last_maintenance_date on the item
            await client.query(`UPDATE items
         SET last_maintenance_date = $1, updated_at = NOW()
         WHERE id = $2`, [data.completed_date || new Date(), data.item_id]);
            // Update user analytics
            await client.query(`UPDATE user_analytics
         SET total_maintenance_completed = total_maintenance_completed + 1,
             updated_at = NOW()
         WHERE user_id = $1`, [userId]);
            // If there is a schedule with prevents_cost, add to preventive savings
            if (data.schedule_id) {
                const scheduleResult = await client.query('SELECT prevents_cost FROM maintenance_schedules WHERE id = $1', [data.schedule_id]);
                if (scheduleResult.rows.length > 0 && scheduleResult.rows[0].prevents_cost) {
                    const preventsCost = parseFloat(scheduleResult.rows[0].prevents_cost);
                    await client.query(`UPDATE user_analytics
             SET total_preventive_savings = total_preventive_savings + $1,
                 updated_at = NOW()
             WHERE user_id = $2`, [preventsCost, userId]);
                }
            }
            await client.query('COMMIT');
            logger_1.logger.info({ entryId: entry.id, userId, itemId: data.item_id }, 'Maintenance logged');
            return entry;
        }
        catch (error) {
            await client.query('ROLLBACK');
            logger_1.logger.error({ error, userId, data }, 'Error logging maintenance');
            throw error;
        }
        finally {
            client.release();
        }
    }
    /**
     * Get maintenance history with pagination and optional itemId filter
     */
    static async getMaintenanceHistory(userId, options = {}) {
        const { limit = 50, offset = 0, itemId } = options;
        try {
            let query = `
        SELECT mh.*,
               i.name as item_name,
               i.brand as item_brand,
               i.category as item_category,
               ms.frequency_label,
               ms.difficulty
        FROM maintenance_history mh
        JOIN items i ON i.id = mh.item_id
        LEFT JOIN maintenance_schedules ms ON ms.id = mh.schedule_id
        WHERE mh.user_id = $1
      `;
            const params = [userId];
            if (itemId) {
                query += ` AND mh.item_id = $${params.length + 1}`;
                params.push(itemId);
            }
            query += ` ORDER BY mh.completed_date DESC, mh.created_at DESC`;
            query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
            params.push(limit, offset);
            const result = await db_1.pool.query(query, params);
            // Get total count
            const countQuery = itemId
                ? 'SELECT COUNT(*) FROM maintenance_history WHERE user_id = $1 AND item_id = $2'
                : 'SELECT COUNT(*) FROM maintenance_history WHERE user_id = $1';
            const countParams = itemId ? [userId, itemId] : [userId];
            const countResult = await db_1.pool.query(countQuery, countParams);
            return {
                history: result.rows,
                total: parseInt(countResult.rows[0].count, 10),
            };
        }
        catch (error) {
            logger_1.logger.error({ error, userId, options }, 'Error fetching maintenance history');
            throw error;
        }
    }
    /**
     * Delete a maintenance log entry
     */
    static async deleteMaintenanceLog(id, userId) {
        const client = await db_1.pool.connect();
        try {
            await client.query('BEGIN');
            // Get the record before deleting (verify ownership and get schedule info)
            const result = await client.query('SELECT id, schedule_id FROM maintenance_history WHERE id = $1 AND user_id = $2', [id, userId]);
            if (result.rows.length === 0) {
                throw new errors_1.AppError('Maintenance log entry not found', 404);
            }
            const entry = result.rows[0];
            // Delete the record
            await client.query('DELETE FROM maintenance_history WHERE id = $1 AND user_id = $2', [id, userId]);
            // Update user analytics
            await client.query(`UPDATE user_analytics
         SET total_maintenance_completed = GREATEST(0, total_maintenance_completed - 1),
             updated_at = NOW()
         WHERE user_id = $1`, [userId]);
            // If there was a schedule with prevents_cost, subtract from preventive savings
            if (entry.schedule_id) {
                const scheduleResult = await client.query('SELECT prevents_cost FROM maintenance_schedules WHERE id = $1', [entry.schedule_id]);
                if (scheduleResult.rows.length > 0 && scheduleResult.rows[0].prevents_cost) {
                    const preventsCost = parseFloat(scheduleResult.rows[0].prevents_cost);
                    await client.query(`UPDATE user_analytics
             SET total_preventive_savings = GREATEST(0, total_preventive_savings - $1),
                 updated_at = NOW()
             WHERE user_id = $2`, [preventsCost, userId]);
                }
            }
            await client.query('COMMIT');
            logger_1.logger.info({ id, userId }, 'Maintenance log entry deleted');
        }
        catch (error) {
            await client.query('ROLLBACK');
            logger_1.logger.error({ error, id, userId }, 'Error deleting maintenance log entry');
            throw error;
        }
        finally {
            client.release();
        }
    }
    /**
     * Calculate total preventive savings from completed maintenance
     */
    static async getPreventiveSavings(userId) {
        try {
            // Get overall totals from user_analytics
            const analyticsResult = await db_1.pool.query(`SELECT total_preventive_savings, total_maintenance_completed
         FROM user_analytics
         WHERE user_id = $1`, [userId]);
            const totalPreventiveSavings = analyticsResult.rows.length > 0
                ? parseFloat(analyticsResult.rows[0].total_preventive_savings) || 0
                : 0;
            const totalTasksCompleted = analyticsResult.rows.length > 0
                ? parseInt(analyticsResult.rows[0].total_maintenance_completed, 10) || 0
                : 0;
            // Get savings breakdown by category
            const categoryResult = await db_1.pool.query(`SELECT
           i.category,
           COUNT(mh.id)::integer as tasks_completed,
           COALESCE(SUM(ms.prevents_cost), 0) as savings
         FROM maintenance_history mh
         JOIN items i ON i.id = mh.item_id
         LEFT JOIN maintenance_schedules ms ON ms.id = mh.schedule_id
         WHERE mh.user_id = $1
         GROUP BY i.category
         ORDER BY savings DESC`, [userId]);
            return {
                total_preventive_savings: totalPreventiveSavings,
                total_tasks_completed: totalTasksCompleted,
                savings_by_category: categoryResult.rows,
            };
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error calculating preventive savings');
            throw error;
        }
    }
}
exports.MaintenanceService = MaintenanceService;
//# sourceMappingURL=maintenance.service.js.map