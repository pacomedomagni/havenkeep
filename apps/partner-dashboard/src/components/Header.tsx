interface HeaderProps {
  title: string
  subtitle?: string
}

export default function Header({ title, subtitle }: HeaderProps) {
  return (
    <div className="bg-haven-surface border-b border-haven-border px-8 py-6">
      <div>
        <h1 className="text-2xl font-bold text-white">{title}</h1>
        {subtitle && <p className="text-haven-text-secondary mt-1">{subtitle}</p>}
      </div>
    </div>
  )
}
