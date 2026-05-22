import type { ReactNode } from "react"
import { cn } from "@/lib/utils"

export function BatteryBar({ level }: { level: number }) {
  const tone =
    level >= 60
      ? "bg-[var(--success)]"
      : level >= 30
      ? "bg-[var(--warning)]"
      : "bg-[var(--destructive)]"
  return (
    <div className="flex items-center gap-2 min-w-0">
      <div className="h-1.5 w-20 rounded-full bg-[var(--surface-high)] overflow-hidden">
        <div className={cn("h-full rounded-full", tone)} style={{ width: `${level}%` }} />
      </div>
      <span className="text-xs font-semibold tabular-nums text-[var(--foreground)]">{level}%</span>
    </div>
  )
}

export function StatusChip({ status }: { status: string }) {
  const map: Record<string, { label: string; cls: string }> = {
    available: { label: "Disponibile", cls: "bg-[var(--secondary-container)] text-[var(--secondary-foreground)]" },
    reserved: { label: "Riservato", cls: "bg-[#fff3d6] text-[var(--warning)]" },
    in_use: { label: "In uso", cls: "bg-[var(--surface-high)] text-[var(--primary)]" },
    maintenance: { label: "Manutenzione", cls: "bg-[#ffe5e5] text-[var(--destructive)]" },
    open: { label: "Aperto", cls: "bg-[#ffe5e5] text-[var(--destructive)]" },
    in_progress: { label: "In lavorazione", cls: "bg-[#fff3d6] text-[var(--warning)]" },
    resolved: { label: "Risolto", cls: "bg-[var(--secondary-container)] text-[var(--secondary-foreground)]" },
    active: { label: "Attiva", cls: "bg-[var(--secondary-container)] text-[var(--secondary-foreground)]" },
    expired: { label: "Scaduta", cls: "bg-[var(--surface-high)] text-[var(--muted-foreground)]" },
    cancelled: { label: "Annullata", cls: "bg-[var(--surface-high)] text-[var(--muted-foreground)]" },
    converted_to_ride: { label: "In corsa", cls: "bg-[var(--surface-high)] text-[var(--primary)]" },
    completed: { label: "Completata", cls: "bg-[var(--secondary-container)] text-[var(--secondary-foreground)]" },
    suspended: { label: "Sospeso", cls: "bg-[#fff3d6] text-[var(--warning)]" },
    blocked: { label: "Bloccato", cls: "bg-[#ffe5e5] text-[var(--destructive)]" },
  }
  const item = map[status] ?? { label: status, cls: "bg-[var(--surface-high)] text-[var(--muted-foreground)]" }
  return (
    <span className={cn("inline-flex items-center rounded-full px-2.5 py-1 text-[0.6875rem] font-bold uppercase tracking-wide", item.cls)}>
      {item.label}
    </span>
  )
}

export function TonalCard({ children, active, className, onClick }: { children: ReactNode; active?: boolean; className?: string; onClick?: () => void }) {
  return (
    <div
      onClick={onClick}
      className={cn(
        "rounded-3xl bg-[var(--surface-lowest)] p-5 transition-all",
        onClick && "cursor-pointer hover:bg-[var(--surface-low)]",
        active && "ghost-active",
        className
      )}
    >
      {children}
    </div>
  )
}

export function VehicleTypeLabel(type: "bike" | "scooter" | "car") {
  return type === "bike" ? "Bici elettrica" : type === "scooter" ? "Monopattino" : "Auto elettrica"
}

export function VehicleEmoji({ type }: { type: "bike" | "scooter" | "car" }) {
  const map = { bike: "🚲", scooter: "🛴", car: "🚗" }
  return (
    <div className="size-14 rounded-2xl bg-[var(--surface-low)] flex items-center justify-center text-3xl">
      {map[type]}
    </div>
  )
}
