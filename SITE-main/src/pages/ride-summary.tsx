import { useEffect, useState } from "react"
import { useNavigate, useParams } from "react-router-dom"
import { Check } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { StatusChip, TonalCard, VehicleEmoji, VehicleTypeLabel } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type Ride, type RideEndDetails, type Vehicle } from "@/lib/supabase"
import { parsePointEwkbHex } from "@/lib/postgis"

type Payment = { id: string; amount: number; status: string; payment_method_id: string }
type Method = { type: string; last4: string }

export function RideSummaryPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [ride, setRide] = useState<Ride | null>(null)
  const [vehicle, setVehicle] = useState<Vehicle | null>(null)
  const [payment, setPayment] = useState<Payment | null>(null)
  const [method, setMethod] = useState<Method | null>(null)
  const [endLoc, setEndLoc] = useState<{ lat: number; lng: number } | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    ;(async () => {
      const { data: r } = await supabase.from("rides").select("*").eq("id", id).maybeSingle()
      if (!r) { setLoading(false); return }
      setRide(r as Ride)
      const { data: v } = await supabase.from("vehicles").select("*").eq("id", (r as Ride).vehicle_id).maybeSingle()
      setVehicle((v as Vehicle) ?? null)
      const { data: p } = await supabase.from("payments").select("*").eq("ride_id", id).maybeSingle()
      if (p) {
        setPayment(p as Payment)
        const { data: m } = await supabase.from("payment_methods").select("type,last4").eq("id", (p as Payment).payment_method_id).maybeSingle()
        setMethod((m as Method) ?? null)
      }
      const { data: details } = await supabase.rpc("ride_end_details", { p_ride_id: id })
      const detail = ((details as RideEndDetails[] | null) ?? [])[0]
      if (detail?.end_lat != null && detail.end_lng != null) {
        setEndLoc({ lat: detail.end_lat, lng: detail.end_lng })
      } else {
        const fallback = await supabase
          .from("rides")
          .select("end_location")
          .eq("id", id)
          .maybeSingle()
        const point = parsePointEwkbHex((fallback.data as { end_location?: string } | null)?.end_location)
        if (point) setEndLoc(point)
      }
      setLoading(false)
    })()
  }, [id])

  if (loading) {
    return (
      <AppShell title="Riepilogo" hideTabs>
        <div className="flex justify-center py-10"><Spinner /></div>
      </AppShell>
    )
  }
  if (!ride || !vehicle) {
    return (
      <AppShell title="Riepilogo" hideTabs>
        <p className="text-[var(--muted-foreground)]">Corsa non trovata.</p>
      </AppShell>
    )
  }

  return (
    <AppShell title="Riepilogo corsa" hideTabs>
      <TonalCard className="text-center">
        <div className="size-14 rounded-full bg-[var(--secondary-container)] flex items-center justify-center mx-auto">
          <Check className="size-7 text-[var(--secondary-foreground)]" />
        </div>
        <p className="text-sm text-[var(--muted-foreground)] mt-3">Pagamento completato</p>
        <p className="text-5xl font-extrabold mt-2 font-display tabular-nums">
          {ride.final_cost?.toFixed(2)} €
        </p>
        <p className="text-sm text-[var(--muted-foreground)] mt-1">
          {ride.duration_minutes} {ride.duration_minutes === 1 ? "minuto" : "minuti"} di corsa
        </p>
      </TonalCard>

      <div className="mt-4 space-y-3">
        <RowCard label="ID corsa" value={ride.id.slice(0, 8).toUpperCase()} mono />
        <RowCard label="Mezzo" value={`${vehicle.code} · ${VehicleTypeLabel(vehicle.type)}`}>
          <VehicleEmoji type={vehicle.type} />
        </RowCard>
        <RowCard label="Metodo di pagamento" value={method ? `${method.type.toUpperCase()} •••• ${method.last4}` : "—"} />
        <RowCard label="Stato pagamento">
          <StatusChip status={payment?.status ?? "pending"} />
        </RowCard>
        {endLoc && <RowCard label="Posizione finale" value={`${endLoc.lat.toFixed(5)}, ${endLoc.lng.toFixed(5)}`} mono />}
      </div>

      <Button onClick={() => navigate("/nearby")} className="mt-6 w-full h-14 rounded-2xl btn-primary-grad font-bold text-base">
        Torna alla home
      </Button>
    </AppShell>
  )
}

function RowCard({ label, value, mono, children }: { label: string; value?: string; mono?: boolean; children?: React.ReactNode }) {
  return (
    <TonalCard>
      <div className="flex items-center justify-between gap-3">
        <p className="label-sm text-[var(--muted-foreground)]">{label.toUpperCase()}</p>
        <div className={mono ? "font-mono text-sm font-semibold" : "text-sm font-semibold"}>
          {value ?? children}
        </div>
      </div>
    </TonalCard>
  )
}
