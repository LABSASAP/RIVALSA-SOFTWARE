import { useEffect, useState } from "react"
import { Link, useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { CreditCard, LockKeyhole, Timer, Clock as Unlock } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import {
  StatusChip,
  TonalCard,
  VehicleCategoryLabel,
  VehicleDisplayName,
  VehicleEmoji,
  VehicleIconType,
  VehicleModelLabel,
  VehiclePricingLabel,
} from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type Reservation, type Vehicle } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"

export function ReservationPage() {
  const navigate = useNavigate()
  const { session } = useAuth()
  const userId = session?.user.id
  const [reservation, setReservation] = useState<Reservation | null>(null)
  const [vehicle, setVehicle] = useState<Vehicle | null>(null)
  const [hasPaymentMethod, setHasPaymentMethod] = useState(false)
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
        const [
          { data: v },
          { count: paymentMethodCount, error: paymentMethodError },
        ] = await Promise.all([
          supabase.from("vehicles").select("*").eq("id", res.vehicle_id).maybeSingle(),
          userId
            ? supabase
                .from("payment_methods")
                .select("id", { count: "exact", head: true })
                .eq("user_id", userId)
            : Promise.resolve({ count: 0, error: null }),
        ])

        setVehicle((v as Vehicle) ?? null)
        if (paymentMethodError) {
          toast.error("Non e stato possibile verificare i metodi di pagamento.")
          setHasPaymentMethod(false)
        } else {
          setHasPaymentMethod((paymentMethodCount ?? 0) > 0)
        }
      }
      setLoading(false)
    })()
  }, [navigate, userId])

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])

  const remainingMs = reservation ? new Date(reservation.expires_at).getTime() - now : 0
  const remaining = Math.max(0, Math.floor(remainingMs / 1000))
  const mm = Math.floor(remaining / 60)
  const ss = remaining % 60
  const expired = remainingMs <= 0
  const isLocked = !!vehicle?.is_remote_locked
  const requiresPaymentMethod = !expired && !isLocked && !hasPaymentMethod

  const unlock = async () => {
    if (!reservation) return
    if (!hasPaymentMethod) {
      toast.warning("Aggiungi un metodo di pagamento per avviare la corsa.")
      return
    }
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
          <VehicleEmoji type={VehicleIconType(vehicle)} />
        </div>
        <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code}</p>
        <h2 className="text-2xl font-extrabold mt-1">{VehicleDisplayName(vehicle)}</h2>
        <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{VehicleModelLabel(vehicle)}</p>
        <div className="mt-3 flex justify-center">
          <StatusChip status={isLocked ? "remote_locked" : "reserved"} />
        </div>
      </TonalCard>

      {isLocked && (
        <TonalCard className="mt-4 bg-[#ffe5e5]">
          <div className="flex items-start gap-3">
            <div className="flex size-11 items-center justify-center rounded-2xl bg-white/70 text-[var(--destructive)]">
              <LockKeyhole className="size-5" />
            </div>
            <div>
              <p className="font-bold text-[var(--destructive)]">Sblocco temporaneamente bloccato</p>
              <p className="mt-1 text-sm text-[var(--destructive)]/80">
                {vehicle.remote_lock_reason || "Un operatore ha bloccato il mezzo da remoto."}
              </p>
            </div>
          </div>
        </TonalCard>
      )}

      {requiresPaymentMethod && (
        <TonalCard className="mt-4 bg-[#fff3d6]">
          <div className="flex items-start gap-3">
            <div className="flex size-11 items-center justify-center rounded-2xl bg-white/70 text-[var(--warning)]">
              <CreditCard className="size-5" />
            </div>
            <div>
              <p className="font-bold text-[var(--warning)]">Metodo di pagamento richiesto</p>
              <p className="mt-1 text-sm leading-relaxed text-[var(--warning)]/85">
                Per sbloccare il mezzo e avviare la corsa devi prima aggiungere un metodo di pagamento.
              </p>
            </div>
          </div>
        </TonalCard>
      )}

      <TonalCard className="mt-4">
        <p className="label-sm text-[var(--muted-foreground)]">TARIFFA {VehicleCategoryLabel(vehicle).toUpperCase()}</p>
        <p className="mt-2 text-sm font-bold text-[var(--primary)]">{VehiclePricingLabel(vehicle)}</p>
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

      {expired || isLocked ? (
        <Button onClick={() => navigate("/nearby")} className="mt-6 w-full h-14 rounded-2xl btn-primary-grad font-bold text-base">
          Torna ai mezzi
        </Button>
      ) : requiresPaymentMethod ? (
        <Button asChild className="mt-6 w-full h-14 rounded-2xl btn-primary-grad font-bold text-base">
          <Link to="/payment-methods?returnTo=/reservation">
            <CreditCard className="size-5" /> Aggiungi metodo di pagamento
          </Link>
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
