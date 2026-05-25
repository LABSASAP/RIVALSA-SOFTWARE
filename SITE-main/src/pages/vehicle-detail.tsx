import { useEffect, useState } from "react"
import { useNavigate, useParams } from "react-router-dom"
import { toast } from "sonner"
import { AppShell } from "@/components/app-shell"
import {
  BatteryBar,
  StatusChip,
  TonalCard,
  VehicleCategoryLabel,
  VehicleDisplayName,
  VehicleEmoji,
  VehicleIconType,
  VehicleModelLabel,
  VehiclePricingLabel,
  formatVehicleHourlyRate,
} from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type Vehicle } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"

export function VehicleDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { profile } = useAuth()
  const [vehicle, setVehicle] = useState<(Vehicle & { lat?: number; lng?: number }) | null>(null)
  const [loading, setLoading] = useState(true)
  const [reserving, setReserving] = useState(false)

  useEffect(() => {
    ;(async () => {
      const { data } = await supabase
        .from("vehicles")
        .select("*")
        .eq("id", id)
        .maybeSingle()
      const { data: pos } = await supabase.rpc("vehicles_nearby", { p_lat: 41.1175, p_lng: 16.872, p_radius: 50000 })
      const match = (pos as Array<{ id: string; lat: number; lng: number }> | null)?.find((v) => v.id === id)
      setVehicle(data ? { ...(data as Vehicle), lat: match?.lat, lng: match?.lng } : null)
      setLoading(false)
    })()
  }, [id])

  const reserve = async () => {
    if (!vehicle) return
    setReserving(true)
    const { error } = await supabase.rpc("reservation_create", { p_vehicle_id: vehicle.id })
    setReserving(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Mezzo prenotato")
    navigate("/reservation")
  }

  if (loading) {
    return (
      <AppShell title="Dettaglio mezzo" back="/nearby">
        <div className="flex justify-center py-10"><Spinner /></div>
      </AppShell>
    )
  }
  if (!vehicle) {
    return (
      <AppShell title="Dettaglio mezzo" back="/nearby">
        <p className="text-[var(--muted-foreground)]">Mezzo non trovato.</p>
      </AppShell>
    )
  }

  const canReserve = profile?.status === "active" && vehicle.status === "available"

  return (
    <AppShell title="Dettaglio mezzo" back="/nearby">
      <TonalCard className="text-center pb-7">
        <div className="flex justify-center mb-4">
          <VehicleEmoji type={VehicleIconType(vehicle)} />
        </div>
        <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code}</p>
        <h2 className="text-2xl font-extrabold mt-1">{VehicleDisplayName(vehicle)}</h2>
        <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{VehicleModelLabel(vehicle)}</p>
        <div className="mt-3 flex justify-center">
          <StatusChip status={vehicle.status} />
        </div>
      </TonalCard>

      <div className="grid grid-cols-2 gap-3 mt-4">
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">BATTERIA</p>
          <div className="mt-2"><BatteryBar level={vehicle.battery_level} /></div>
        </TonalCard>
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">CATEGORIA</p>
          <p className="font-bold text-sm mt-2">{VehicleCategoryLabel(vehicle)}</p>
        </TonalCard>
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">TARIFFA</p>
          <p className="text-xs font-semibold mt-2 leading-relaxed text-[var(--primary)]">{VehiclePricingLabel(vehicle)}</p>
        </TonalCard>
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">ORARIA</p>
          <p className="font-bold text-sm mt-2">{formatVehicleHourlyRate(vehicle.hourly_rate)}</p>
        </TonalCard>
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">AUTONOMIA</p>
          <p className="font-bold text-sm mt-2">{vehicle.range_km ? `${vehicle.range_km} km` : "n/d"}</p>
        </TonalCard>
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">COORDINATE</p>
          <p className="font-mono text-xs mt-2 leading-relaxed">
            {vehicle.lat?.toFixed(4) ?? "—"}<br />
            {vehicle.lng?.toFixed(4) ?? "—"}
          </p>
        </TonalCard>
      </div>

      <Button
        onClick={reserve}
        disabled={!canReserve || reserving}
        className="mt-6 w-full h-14 rounded-2xl btn-primary-grad font-bold text-base"
      >
        {reserving ? <Spinner /> : "Prenota mezzo"}
      </Button>

      {!canReserve && profile?.status !== "active" && (
        <p className="mt-3 text-sm text-[var(--destructive)] text-center">
          Il tuo account non è attivo, non puoi prenotare.
        </p>
      )}
      {!canReserve && vehicle.status !== "available" && profile?.status === "active" && (
        <p className="mt-3 text-sm text-[var(--muted-foreground)] text-center">
          Mezzo non disponibile in questo momento.
        </p>
      )}
    </AppShell>
  )
}
