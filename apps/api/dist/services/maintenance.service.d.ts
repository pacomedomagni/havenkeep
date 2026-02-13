import { MaintenanceSchedule, MaintenanceHistory, CreateMaintenanceHistoryDto, ItemCategory } from '../types/database.types';
export declare class MaintenanceService {
    /**
     * Get maintenance schedules for a given item category
     */
    static getSchedulesByCategory(category: ItemCategory): Promise<MaintenanceSchedule[]>;
    /**
     * Get due/overdue maintenance tasks for a specific item
     * Compares schedules for the item's category against maintenance history
     */
    static getItemMaintenanceDue(userId: string, itemId: string): Promise<{
        item: {
            id: string;
            name: string;
            category: ItemCategory;
        };
        tasks: Array<{
            schedule: MaintenanceSchedule;
            last_completed: Date | null;
            next_due: Date;
            is_overdue: boolean;
            days_until_due: number;
        }>;
    }>;
    /**
     * Get all due maintenance across all user items
     */
    static getUserMaintenanceSummary(userId: string): Promise<{
        total_due: number;
        total_overdue: number;
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
            }>;
        }>;
    }>;
    /**
     * Log a completed maintenance task
     */
    static logMaintenance(userId: string, data: CreateMaintenanceHistoryDto): Promise<MaintenanceHistory>;
    /**
     * Get maintenance history with pagination and optional itemId filter
     */
    static getMaintenanceHistory(userId: string, options?: {
        limit?: number;
        offset?: number;
        itemId?: string;
    }): Promise<{
        history: MaintenanceHistory[];
        total: number;
    }>;
    /**
     * Delete a maintenance log entry
     */
    static deleteMaintenanceLog(id: string, userId: string): Promise<void>;
    /**
     * Calculate total preventive savings from completed maintenance
     */
    static getPreventiveSavings(userId: string): Promise<{
        total_preventive_savings: number;
        total_tasks_completed: number;
        savings_by_category: Array<{
            category: ItemCategory;
            tasks_completed: number;
            savings: number;
        }>;
    }>;
}
//# sourceMappingURL=maintenance.service.d.ts.map