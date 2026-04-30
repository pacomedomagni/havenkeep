import { pool } from '../db';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';
import { addMonthsSafe } from '../utils/dates';
import { decimalToCents } from '../utils/money';
import {
  MaintenanceSchedule,
  MaintenanceHistory,
  CreateMaintenanceHistoryDto,
  ItemCategory,
} from '../types/database.types';

export class MaintenanceService {
  /**
   * Get maintenance schedules for a given item category
   */
  static async getSchedulesByCategory(
    category: ItemCategory
  ): Promise<MaintenanceSchedule[]> {
    try {
      const result = await pool.query(
        `SELECT *
         FROM maintenance_schedules
         WHERE category = $1
         ORDER BY priority ASC, task_name ASC`,
        [category]
      );

      return result.rows;
    } catch (error) {
      logger.error({ error, category }, 'Error fetching maintenance schedules');
      throw error;
    }
  }

  /**
   * Get due/overdue maintenance tasks for a specific item
   * Compares schedules for the item's category against maintenance history
   */
  static async getItemMaintenanceDue(
    userId: string,
    itemId: string
  ): Promise<{
    item: { id: string; name: string; category: ItemCategory };
    tasks: Array<{
      schedule: MaintenanceSchedule;
      last_completed: Date | null;
      next_due: Date;
      is_overdue: boolean;
      days_until_due: number;
    }>;
  }> {
    try {
      // Verify item belongs to user and get item details
      const itemResult = await pool.query(
        `SELECT id, name, category, purchase_date, installation_date
         FROM items
         WHERE id = $1 AND user_id = $2`,
        [itemId, userId]
      );

      if (itemResult.rows.length === 0) {
        throw new AppError('Item not found or does not belong to user', 404);
      }

      const item = itemResult.rows[0];

      // Get all schedules for this item's category
      const schedulesResult = await pool.query(
        `SELECT *
         FROM maintenance_schedules
         WHERE category = $1
         ORDER BY priority ASC, task_name ASC`,
        [item.category]
      );

      // Get the most recent maintenance history for each schedule on this item
      const historyResult = await pool.query(
        `SELECT DISTINCT ON (schedule_id)
           schedule_id,
           completed_date
         FROM maintenance_history
         WHERE item_id = $1 AND user_id = $2 AND schedule_id IS NOT NULL
         ORDER BY schedule_id, completed_date DESC`,
        [itemId, userId]
      );

      // Build a map of schedule_id -> last completed date
      const historyMap = new Map<string, Date>();
      for (const row of historyResult.rows) {
        historyMap.set(row.schedule_id, row.completed_date);
      }

      const now = new Date();
      const itemStartDate = item.installation_date || item.purchase_date || item.created_at;

      const tasks = schedulesResult.rows.map((schedule: MaintenanceSchedule) => {
        const lastCompleted = historyMap.get(schedule.id) || null;

        // Calculate next due date: from last completion, or from item start date
        const baseDate = lastCompleted ? new Date(lastCompleted) : new Date(itemStartDate);
        const nextDue = addMonthsSafe(baseDate, schedule.frequency_months);

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
    } catch (error) {
      logger.error({ error, userId, itemId }, 'Error fetching item maintenance due');
      throw error;
    }
  }

  /**
   * Get all due maintenance across all user items.
   *
   * 2.13: optional [homeId] scopes the result to a single home so the
   * mobile home-switcher actually filters maintenance instead of leaking
   * tasks from other homes onto the dashboard.
   */
  static async getUserMaintenanceSummary(userId: string, homeId?: string): Promise<{
    total_due: number;
    total_overdue: number;
    // F026: surface whether a user has zero items, no schedules, or just
    // happens to be caught up — three states the dashboard wants to render
    // differently.
    summary_state: 'no_items' | 'no_schedules' | 'caught_up' | 'has_due';
    items: Array<{
      item_id: string;
      item_name: string;
      category: ItemCategory;
      due_count: number;
      overdue_count: number;
      tasks: Array<{
        schedule_id: string;
        task_name: string;
        next_due: Date;
        is_overdue: boolean;
        days_until_due: number;
        priority: number;
        is_required_for_warranty: boolean;
        how_to_url: string | null;
        video_url: string | null;
        frequency_label: string | null;
      }>;
    }>;
  }> {
    try {
      // Get all non-archived items for the user (optionally home-scoped).
      const itemsResult = await pool.query(
        `SELECT id, name, category, purchase_date, installation_date, created_at
           FROM items
          WHERE user_id = $1 AND is_archived = FALSE
            AND ($2::uuid IS NULL OR home_id = $2::uuid)
          ORDER BY name ASC`,
        [userId, homeId ?? null]
      );

      if (itemsResult.rows.length === 0) {
        return { total_due: 0, total_overdue: 0, summary_state: 'no_items', items: [] };
      }

      // Get all unique categories from user's items
      const categories = [...new Set(itemsResult.rows.map((i: any) => i.category))];

      // Get all schedules for those categories
      const schedulesResult = await pool.query(
        `SELECT *
         FROM maintenance_schedules
         WHERE category = ANY($1)
         ORDER BY priority ASC`,
        [categories]
      );

      // Build a map of category -> schedules
      const schedulesByCategory = new Map<string, MaintenanceSchedule[]>();
      for (const schedule of schedulesResult.rows) {
        const list = schedulesByCategory.get(schedule.category) || [];
        list.push(schedule);
        schedulesByCategory.set(schedule.category, list);
      }

      // Get all maintenance history for the user's items
      const itemIds = itemsResult.rows.map((i: any) => i.id);
      const historyResult = await pool.query(
        `SELECT DISTINCT ON (item_id, schedule_id)
           item_id,
           schedule_id,
           completed_date
         FROM maintenance_history
         WHERE item_id = ANY($1) AND user_id = $2 AND schedule_id IS NOT NULL
         ORDER BY item_id, schedule_id, completed_date DESC`,
        [itemIds, userId]
      );

      // Build a map of "itemId:scheduleId" -> last completed date
      const historyMap = new Map<string, Date>();
      for (const row of historyResult.rows) {
        historyMap.set(`${row.item_id}:${row.schedule_id}`, row.completed_date);
      }

      const now = new Date();
      let totalDue = 0;
      let totalOverdue = 0;

      const items = itemsResult.rows
        .map((item: any) => {
          const schedules = schedulesByCategory.get(item.category) || [];
          const itemStartDate = item.installation_date || item.purchase_date || item.created_at;

          const tasks = schedules.map((schedule: MaintenanceSchedule) => {
            const lastCompleted = historyMap.get(`${item.id}:${schedule.id}`) || null;
            const baseDate = lastCompleted ? new Date(lastCompleted) : new Date(itemStartDate);
            const nextDue = addMonthsSafe(baseDate, schedule.frequency_months);

            const diffMs = nextDue.getTime() - now.getTime();
            const daysUntilDue = Math.ceil(diffMs / (1000 * 60 * 60 * 24));

            return {
              schedule_id: schedule.id,
              task_name: schedule.task_name,
              next_due: nextDue,
              is_overdue: daysUntilDue < 0,
              days_until_due: daysUntilDue,
              priority: schedule.priority,
              is_required_for_warranty: schedule.is_required_for_warranty,
              how_to_url: schedule.how_to_url,
              video_url: schedule.video_url,
              frequency_label: schedule.frequency_label,
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
        .filter((item: any) => item.tasks.length > 0);

      // Sort items by most overdue tasks first
      items.sort((a: any, b: any) => b.overdue_count - a.overdue_count);

      // F026: pick the right summary_state.
      const totalSchedules = schedulesResult.rows.length;
      const summaryState: 'no_items' | 'no_schedules' | 'caught_up' | 'has_due' =
        totalSchedules === 0 ? 'no_schedules' :
        totalDue === 0 ? 'caught_up' : 'has_due';

      return {
        total_due: totalDue,
        total_overdue: totalOverdue,
        summary_state: summaryState,
        items,
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching user maintenance summary');
      throw error;
    }
  }

  /**
   * Log a completed maintenance task
   */
  static async logMaintenance(
    userId: string,
    data: CreateMaintenanceHistoryDto
  ): Promise<MaintenanceHistory> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Verify item belongs to user and is not archived
      const itemCheck = await client.query(
        'SELECT id FROM items WHERE id = $1 AND user_id = $2 AND is_archived = FALSE',
        [data.itemId, userId]
      );

      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found or is archived', 404);
      }

      // If scheduleId is provided, verify it exists
      if (data.scheduleId) {
        const scheduleCheck = await client.query(
          'SELECT id FROM maintenance_schedules WHERE id = $1',
          [data.scheduleId]
        );

        if (scheduleCheck.rows.length === 0) {
          throw new AppError('Maintenance schedule not found', 404);
        }
      }

      // Insert maintenance history record
      const result = await client.query(
        `INSERT INTO maintenance_history (
          item_id, user_id, schedule_id, task_name,
          completed_date, notes, duration_minutes, cost
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *`,
        [
          data.itemId,
          userId,
          data.scheduleId || null,
          data.taskName,
          data.completedDate || new Date(),
          data.notes || null,
          data.durationMinutes || null,
          data.cost || 0,
        ]
      );

      const entry = result.rows[0];

      // F025: UPDATE includes user_id so a row that briefly sat under a
      // different owner can't be touched by this user even if the item id
      // somehow leaked.
      await client.query(
        `UPDATE items
         SET last_maintenance_date = $1, updated_at = NOW()
         WHERE id = $2 AND user_id = $3`,
        [data.completedDate || new Date(), data.itemId, userId]
      );

      // F030: a single UPSERT writes both the counter and the preventive
      // savings delta, with COALESCE guarding NULL columns. The previous
      // two-statement form would silently drop the savings update if the
      // user_analytics row already existed but `prevents_cost` was NULL.
      let preventsCostCents = 0;
      if (data.scheduleId) {
        const scheduleResult = await client.query(
          'SELECT prevents_cost FROM maintenance_schedules WHERE id = $1',
          [data.scheduleId]
        );
        if (scheduleResult.rows.length > 0) {
          preventsCostCents = decimalToCents(scheduleResult.rows[0].prevents_cost);
        }
      }

      await client.query(
        `INSERT INTO user_analytics (user_id, total_maintenance_completed, total_preventive_savings)
         VALUES ($1, 1, ($2::bigint)::numeric / 100)
         ON CONFLICT (user_id)
         DO UPDATE SET total_maintenance_completed = COALESCE(user_analytics.total_maintenance_completed, 0) + 1,
                       total_preventive_savings    = COALESCE(user_analytics.total_preventive_savings, 0) + ($2::bigint)::numeric / 100,
                       updated_at                   = NOW()`,
        [userId, preventsCostCents]
      );

      await client.query('COMMIT');

      logger.info({ entryId: entry.id, userId, itemId: data.itemId }, 'Maintenance logged');

      return entry;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      logger.error({ error, userId, data }, 'Error logging maintenance');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get maintenance history with pagination and optional itemId / homeId filter.
   *
   * 2.13: when [homeId] is supplied, the JOIN restricts to items in that
   * home so the count and rows agree with the home-switcher state.
   */
  static async getMaintenanceHistory(
    userId: string,
    options: {
      limit?: number;
      offset?: number;
      itemId?: string;
      homeId?: string;
    } = {}
  ): Promise<{ history: MaintenanceHistory[]; total: number }> {
    const { limit = 50, offset = 0, itemId, homeId } = options;

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
      const params: any[] = [userId];

      if (itemId) {
        query += ` AND mh.item_id = $${params.length + 1}`;
        params.push(itemId);
      }
      if (homeId) {
        query += ` AND i.home_id = $${params.length + 1}`;
        params.push(homeId);
      }

      query += ` ORDER BY mh.completed_date DESC, mh.created_at DESC`;
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      // Total count must mirror the JOIN + filters above so pagination.total
      // doesn't drift after the home-switcher narrows the result set.
      let countQuery = `
        SELECT COUNT(*)
          FROM maintenance_history mh
          JOIN items i ON i.id = mh.item_id
         WHERE mh.user_id = $1
      `;
      const countParams: any[] = [userId];
      if (itemId) {
        countQuery += ` AND mh.item_id = $${countParams.length + 1}`;
        countParams.push(itemId);
      }
      if (homeId) {
        countQuery += ` AND i.home_id = $${countParams.length + 1}`;
        countParams.push(homeId);
      }
      const countResult = await pool.query(countQuery, countParams);

      return {
        history: result.rows,
        total: parseInt(countResult.rows[0].count, 10),
      };
    } catch (error) {
      logger.error({ error, userId, options }, 'Error fetching maintenance history');
      throw error;
    }
  }

  /**
   * Delete a maintenance log entry
   */
  static async deleteMaintenanceLog(id: string, userId: string): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Get the record before deleting (verify ownership and get schedule info)
      const result = await client.query(
        'SELECT id, schedule_id FROM maintenance_history WHERE id = $1 AND user_id = $2',
        [id, userId]
      );

      if (result.rows.length === 0) {
        throw new AppError('Maintenance log entry not found', 404);
      }

      const entry = result.rows[0];

      // Delete the record
      await client.query(
        'DELETE FROM maintenance_history WHERE id = $1 AND user_id = $2',
        [id, userId]
      );

      // Update user analytics
      await client.query(
        `UPDATE user_analytics
         SET total_maintenance_completed = GREATEST(0, total_maintenance_completed - 1),
             updated_at = NOW()
         WHERE user_id = $1`,
        [userId]
      );

      // F004: subtract via cents so float drift can't push the aggregate
      // negative on rows where the original log had a fractional cost.
      if (entry.schedule_id) {
        const scheduleResult = await client.query(
          'SELECT prevents_cost FROM maintenance_schedules WHERE id = $1',
          [entry.schedule_id]
        );

        if (scheduleResult.rows.length > 0 && scheduleResult.rows[0].prevents_cost) {
          const preventsCents = decimalToCents(scheduleResult.rows[0].prevents_cost);

          await client.query(
            `UPDATE user_analytics
             SET total_preventive_savings = GREATEST(0, total_preventive_savings - ($1::bigint)::numeric / 100),
                 updated_at = NOW()
             WHERE user_id = $2`,
            [preventsCents, userId]
          );
        }
      }

      await client.query('COMMIT');

      logger.info({ id, userId }, 'Maintenance log entry deleted');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      logger.error({ error, id, userId }, 'Error deleting maintenance log entry');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Calculate total preventive savings from completed maintenance
   */
  static async getPreventiveSavings(userId: string): Promise<{
    total_preventive_savings: number;
    total_tasks_completed: number;
    savings_by_category: Array<{
      category: ItemCategory;
      tasks_completed: number;
      savings: number;
    }>;
  }> {
    try {
      // Get overall totals from user_analytics
      const analyticsResult = await pool.query(
        `SELECT total_preventive_savings, total_maintenance_completed
         FROM user_analytics
         WHERE user_id = $1`,
        [userId]
      );

      const totalPreventiveSavings = analyticsResult.rows.length > 0
        ? parseFloat(analyticsResult.rows[0].total_preventive_savings) || 0
        : 0;

      const totalTasksCompleted = analyticsResult.rows.length > 0
        ? parseInt(analyticsResult.rows[0].total_maintenance_completed, 10) || 0
        : 0;

      // Get savings breakdown by category. F029: collapse duplicate
      // maintenance_history rows for the same (schedule_id, completed_date)
      // before summing, so a user that re-logged the same task on the same
      // day can't inflate `prevents_cost`. Migration 062 adds a UNIQUE
      // covering the same key — this query layer is belt + suspenders.
      const categoryResult = await pool.query(
        `WITH dedup AS (
           SELECT DISTINCT ON (mh.user_id, mh.item_id, mh.schedule_id, mh.completed_date)
                  mh.id, mh.item_id, mh.schedule_id
             FROM maintenance_history mh
            WHERE mh.user_id = $1 AND mh.schedule_id IS NOT NULL
         )
         SELECT
           i.category,
           COUNT(d.id)::integer as tasks_completed,
           COALESCE(SUM(ms.prevents_cost), 0) as savings
         FROM dedup d
         JOIN items i ON i.id = d.item_id
         LEFT JOIN maintenance_schedules ms ON ms.id = d.schedule_id
         GROUP BY i.category
         ORDER BY savings DESC`,
        [userId]
      );

      return {
        total_preventive_savings: totalPreventiveSavings,
        total_tasks_completed: totalTasksCompleted,
        savings_by_category: categoryResult.rows,
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error calculating preventive savings');
      throw error;
    }
  }
}
