import type { ReactNode } from "react"
import { Bike, CarFront, CircleDot } from "lucide-react"
import type { VehicleCategory, VehicleType } from "@/lib/supabase"
import { cn } from "@/lib/utils"

function batteryTone(level: number) {
  return level >= 60
    ? "bg-[var(--success)]"
    : level >= 30
    ? "bg-[var(--warning)]"
    : "bg-[var(--destructive)]"
}

function batteryLabel(level: number) {
  return level >= 60 ? "Alta" : level >= 30 ? "Media" : "Bassa"
}

export function BatteryBar({ level }: { level: number }) {
  const tone = batteryTone(level)

  return (
    <div className="flex items-center gap-2 min-w-0">
      <div className="h-1.5 w-20 rounded-full bg-[var(--surface-high)] overflow-hidden">
        <div className={cn("h-full rounded-full", tone)} style={{ width: `${level}%` }} />
      </div>
      <span className="text-xs font-semibold tabular-nums text-[var(--foreground)]">{level}%</span>
    </div>
  )
}

export function BatteryMeter({ level }: { level: number }) {
  const tone = batteryTone(level)

  return (
    <div className="min-w-0">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="label-sm text-[var(--muted-foreground)]">Batteria</p>
          <p className="mt-1 text-2xl font-extrabold tabular-nums">{level}%</p>
        </div>
        <span className={cn("rounded-full px-3 py-1 text-xs font-bold", tone, "text-white")}>
          {batteryLabel(level)}
        </span>
      </div>
      <div className="mt-3 h-2.5 overflow-hidden rounded-full bg-[var(--surface-high)]" aria-label={`Batteria ${level}%`}>
        <div className={cn("h-full rounded-full", tone)} style={{ width: `${level}%` }} />
      </div>
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

type VehicleCatalogLike = {
  code?: string
  type: VehicleType
  vehicle_type?: VehicleType | null
  brand?: string | null
  model?: string | null
  display_name?: string | null
  category?: VehicleCategory | string | null
  unlock_fee?: number | null
  price_per_minute?: number | null
  hourly_rate?: number | null
  range_km?: number | null
}

export function VehicleTypeLabel(type: VehicleType) {
  return type === "bike" ? "Bici elettrica" : type === "scooter" ? "Monopattino" : "Auto elettrica"
}

export function VehicleIconType(vehicle: VehicleCatalogLike): VehicleType {
  return vehicle.vehicle_type ?? vehicle.type
}

function cleanText(value: string | null | undefined) {
  return value?.trim() || ""
}

export function VehicleDisplayName(vehicle: VehicleCatalogLike) {
  const displayName = cleanText(vehicle.display_name)
  if (displayName) return displayName

  const modelName = [cleanText(vehicle.brand), cleanText(vehicle.model)].filter(Boolean).join(" ").trim()
  if (modelName) return modelName

  return VehicleTypeLabel(VehicleIconType(vehicle))
}

export function VehicleModelLabel(vehicle: VehicleCatalogLike) {
  const modelName = [cleanText(vehicle.brand), cleanText(vehicle.model)].filter(Boolean).join(" ").trim()
  if (modelName && modelName !== VehicleDisplayName(vehicle)) return modelName
  return VehicleCategoryLabel(vehicle)
}

export function VehicleCategoryLabel(vehicle: VehicleCatalogLike) {
  const map: Record<string, string> = {
    bike: "Bici elettrica",
    scooter: "Monopattino elettrico",
    economy_car: "City car elettrica",
    standard_car: "Auto elettrica standard",
    premium_car: "Auto elettrica premium",
  }
  const category = vehicle.category?.toString()
  return category ? map[category] ?? category : VehicleTypeLabel(VehicleIconType(vehicle))
}

export function formatVehicleMoney(value: number | null | undefined) {
  const parsed = Number(value)
  if (value == null || !Number.isFinite(parsed) || parsed <= 0) return "n/d"
  return `${parsed.toFixed(2)} EUR`
}

export function VehiclePricingLabel(vehicle: VehicleCatalogLike) {
  return `${formatVehicleMoney(vehicle.unlock_fee)} sblocco - ${formatVehicleMoney(vehicle.price_per_minute)}/min`
}

export function formatVehicleHourlyRate(value: number | null | undefined) {
  const money = formatVehicleMoney(value)
  return money === "n/d" ? money : `${money}/h`
}

export function VehicleEmoji({ type }: { type: VehicleType }) {
  const Icon = type === "bike" ? Bike : type === "scooter" ? CircleDot : CarFront
  return (
    <div className="size-14 rounded-2xl bg-[var(--surface-low)] flex items-center justify-center text-[var(--primary)]">
      <Icon className="size-7" />
    </div>
  )
}
