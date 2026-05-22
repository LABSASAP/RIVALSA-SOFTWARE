import { useEffect, useState } from "react"
import { useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { Timer, Clock as Unlock } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { StatusChip, TonalCard, VehicleEmoji, VehicleTypeLabel } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type Reservation, type Vehicle } from "@/lib/supabase"

export function ReservationPage() {
  const navigate = useNavigate()
  const [reservation, setReservation] = useState<Reservation | null>(null)
  const [vehicle, setVehicle] = useState<Vehicle | null>(null)
  const [now, setNow] = useState(Date.now())
  const [unlocking, setUnlocking] = useState(false)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    ;(async () => {
      await supabase.rpc("reservation_expire_stale")
      const { data: res } = await supabase
        .from("reservations")
        .select("*")
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle()
      if (!res) {
        const { data: ride } = await supabase
          .from("rides")
          .select("*")
          .eq("status", "active")
          .maybeSingle()
        if (ride) {
          navigate("/ride")
          return
        }
      }
      setReservation((res as Reservation) ?? null)
      if (res) {
        const { data: v } = await supabase.from("vehicles").select("*").eq("id", res.vehicle_id).maybeSingle()
        setVehicle((v as Vehicle) ?? null)
      }
      setLoading(false)
    })()
  }, [navigate])

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])

  const remainingMs = reservation ? new Date(reservation.expires_at).getTime() - now : 0
  const remaining = Math.max(0, Math.floor(remainingMs / 1000))
  const mm = Math.floor(remaining / 60)
  const ss = remaining % 60
  const expired = remainingMs <= 0

  const unlock = async () => {
    if (!reservation) return
    setUnlocking(true)
    const { data, error } = await supabase.rpc("ride_unlock", { p_reservation_id: reservation.id })
    setUnlocking(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Mezzo sbloccato. Buon viaggio!")
    if (data) navigate("/ride")
  }

  if (loading) {
    return (
      <AppShell title="Prenotazione" back="/nearby">
        <div className="flex justify-center py-10"><Spinner /></div>
      </AppShell>
    )
  }
  if (!reservation || !vehicle) {
    return (
      <AppShell title="Prenotazione" back="/nearby">
        <TonalCard className="text-center py-10">
          <p className="text-[var(--muted-foreground)]">Nessuna prenotazione attiva.</p>
          <Button onClick={() => navigate("/nearby")} className="mt-5 h-12 rounded-2xl btn-primary-grad px-6 font-bold">
            Trova un mezzo
          </Button>
        </TonalCard>
      </AppShell>
    )
  }

  return (
    <AppShell title="Prenotazione attiva" back="/nearby">
      <TonalCard className="text-center">
        <div className="flex justify-center mb-3">
          <VehicleEmoji type={vehicle.type} />
        </div>
        <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code}</p>
        <h2 className="text-2xl font-extrabold mt-1">{VehicleTypeLabel(vehicle.type)}</h2>
        <div className="mt-3 flex justify-center">
          <StatusChip status="reserved" />
        </div>
      </TonalCard>

      <TonalCard className={`mt-4 ${expired ? "" : "ghost-active"}`}>
        <div className="flex items-center gap-3">
          <div className="size-12 rounded-2xl bg-[var(--surface-low)] flex items-center justify-center">
            <Timer className="size-5 text-[var(--primary)]" />
          </div>
          <div className="flex-1">
            <p className="label-sm text-[var(--muted-foreground)]">{expired ? "PRENOTAZIONE SCADUTA" : "TEMPO RESIDUO"}</p>
            <p className="text-3xl font-extrabold tabular-nums leading-tight">
              {String(mm).padStart(2, "0")}:{String(ss).padStart(2, "0")}
            </p>
          </div>
        </div>
      </TonalCard>

      {expired ? (
        <Button onClick={() => navigate("/nearby")} className="mt-6 w-full h-14 rounded-2xl btn-primary-grad font-bold text-base">
          Torna ai mezzi
        </Button>
      ) : (
        <Button onClick={unlock} disabled={unlocking} className="mt-6 w-full h-14 rounded-2xl btn-primary-grad font-bold text-base">
          {unlocking ? <Spinner /> : (
            <>
              <Unlock className="size-5" /> Sblocca mezzo
            </>
          )}
        </Button>
      )}
    </AppShell>
  )
}
