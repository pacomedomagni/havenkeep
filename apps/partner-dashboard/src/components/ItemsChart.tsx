'use client'

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

interface ItemsChartProps {
  data: Array<{ date: string; items_created: number }>
}

export default function ItemsChart({ data }: ItemsChartProps) {
  const formattedData = data.map(d => ({
    date: new Date(d.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    items: d.items_created,
  }))

  return (
    <div className="card">
      <h3 className="text-lg font-semibold text-white mb-4">Daily Items Created (Last 30 Days)</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={formattedData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#2A2A2A" />
          <XAxis
            dataKey="date"
            stroke="#707070"
            style={{ fontSize: '12px' }}
          />
          <YAxis
            stroke="#707070"
            style={{ fontSize: '12px' }}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: '#1E1E1E',
              border: '1px solid #2A2A2A',
              borderRadius: '8px',
              color: '#FFFFFF',
            }}
            labelStyle={{ color: '#B0B0B0' }}
          />
          <Bar
            dataKey="items"
            fill="#BB86FC"
            radius={[4, 4, 0, 0]}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
