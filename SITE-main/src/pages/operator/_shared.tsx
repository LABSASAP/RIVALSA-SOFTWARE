import type { ReactNode } from "react"
import { cn } from "@/lib/utils"

export function PageHeader({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return (
    <div className="px-10 pt-9 pb-5 glass-header flex items-end justify-between gap-4">
      <div>
        <p className="label-sm text-[var(--muted-foreground)]">DASHBOARD OPERATORE</p>
        <h1 className="text-3xl font-extrabold tracking-tight mt-1">{title}</h1>
        {subtitle && <p className="text-[var(--muted-foreground)] mt-1">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

export function PageBody({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("px-10 pb-12 pt-2", className)}>{children}</div>
}

export function StatCard({ label, value, tone }: { label: string; value: string | number; tone?: "primary" | "warning" | "danger" }) {
  return (
    <div className="rounded-3xl bg-[var(--surface-lowest)] p-5">
      <p className="label-sm text-[var(--muted-foreground)]">{label}</p>
      <p
        className={cn(
          "text-3xl font-extrabold mt-1 font-display tabular-nums",
          tone === "warning" && "text-[var(--warning)]",
          tone === "danger" && "text-[var(--destructive)]",
          tone === "primary" && "text-[var(--primary)]"
        )}
      >
        {value}
      </p>
    </div>
  )
}
