import React from 'react';

interface KpiCardProps {
  icon: React.ForwardRefExoticComponent<
    React.PropsWithoutRef<React.SVGProps<SVGSVGElement>> & {
      title?: string;
      titleId?: string;
    } & React.RefAttributes<SVGSVGElement>
  >;
  value: string;
  label: string;
  trend?: {
    value: number;
    isPositive: boolean;
  };
}

export default function KpiCard({ icon: Icon, value, label, trend }: KpiCardProps) {
  return (
    <div className="card hover:border-haven-primary/30 transition-colors duration-200">
      <div className="flex items-start justify-between">
        <div className="w-10 h-10 bg-haven-primary/15 rounded-lg flex items-center justify-center">
          <Icon className="w-5 h-5 text-haven-primary" />
        </div>
        {trend && (
          <span
            className={`inline-flex items-center text-xs font-medium ${
              trend.isPositive ? 'text-haven-active' : 'text-haven-error'
            }`}
          >
            {trend.isPositive ? '+' : '-'}
            {trend.value}%
          </span>
        )}
      </div>
      <div className="mt-4">
        <p className="text-2xl font-bold text-white">{value}</p>
        <p className="text-sm text-haven-text-secondary mt-1">{label}</p>
      </div>
    </div>
  );
}
