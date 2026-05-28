import { useEffect, useRef, useState } from "react"
import { useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { Pause, Play, Square } from "lucide-react"
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
import { Checkbox } from "@/components/ui/checkbox"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type CreditWallet, type Ride, type Vehicle } from "@/lib/supabase"

export function RidePage() {
  const navigate = useNavigate()
  const [ride, setRide] = useState<Ride | null>(null)
  const [vehicle, setVehicle] = useState<Vehicle | null>(null)
  const [now, setNow] = useState(Date.now())
  const [ending, setEnding] = useState(false)
  const [loading, setLoading] = useState(true)
  const [wallet, setWallet] = useState<CreditWallet | null>(null)
  const [applyCredits, setApplyCredits] = useState(false)
  const [currentPosition, setCurrentPosition] = useState(() => ({
    lat: 41.1185 + Math.random() * 0.001,
    lng: 16.874 + Math.random() * 0.001,
  }))
  const positionRef = useRef(currentPosition)

  useEffect(() => {
    ;(async () => {
      const { data: r } = await supabase
        .from("rides")
        .select("*")
        .eq("status", "active")
        .order("started_at", { ascending: false })
        .limit(1)
        .maybeSingle()
      if (r) {
        setRide(r as Ride)
        const { data: v } = await supabase.from("vehicles").select("*").eq("id", (r as Ride).vehicle_id).maybeSingle()
        setVehicle((v as Vehicle) ?? null)
      }
      const { data: walletData } = await supabase.rpc("credit_wallet_get")
      setWallet((Array.isArray(walletData) ? walletData[0] : walletData) as CreditWallet | null)
      setLoading(false)
    })()
  }, [])

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])

  useEffect(() => {
    if (!ride || ride.pause_status === "paused") return

    const nextPosition = () => {
      const current = positionRef.current
      const next = {
        lat: current.lat + (Math.random() - 0.35) * 0.00022,
        lng: current.lng + (Math.random() - 0.35) * 0.00022,
      }
      positionRef.current = next
      setCurrentPosition(next)
      return next
    }

    const record = async () => {
      const next = nextPosition()
      await supabase.rpc("ride_position_record", {
        p_ride_id: ride.id,
        p_lat: next.lat,
        p_lng: next.lng,
      })
    }

    void record()
    const id = window.setInterval(() => { void record() }, 15000)
    return () => window.clearInterval(id)
  }, [ride?.id, ride?.pause_status])

  const pauseStarted = ride?.paused_at ? new Date(ride.paused_at).getTime() : null
  const pausedLiveSeconds = ride?.pause_status === "paused" && pauseStarted ? Math.max(0, Math.floor((now - pauseStarted) / 1000)) : 0
  const totalPaused = (ride?.total_paused_seconds ?? 0) + pausedLiveSeconds
  const totalElapsedSec = ride ? Math.max(0, Math.floor((now - new Date(ride.started_at).getTime()) / 1000)) : 0
  const elapsedSec = ride ? Math.max(0, totalElapsedSec - totalPaused) : 0
  const hh = Math.floor(elapsedSec / 3600)
  const mm = Math.floor((elapsedSec % 3600) / 60)
  const ss = elapsedSec % 60
  const totalHh = Math.floor(totalElapsedSec / 3600)
  const totalMm = Math.floor((totalElapsedSec % 3600) / 60)
  const totalSs = totalElapsedSec % 60

  const togglePause = async () => {
    if (!ride) return
    const fn = ride.pause_status === "paused" ? "ride_resume" : "ride_pause"
    const { data, error } = await supabase.rpc(fn, { p_ride_id: ride.id })
    if (error) {
      toast.error(error.message)
      return
    }
    setRide(data as Ride)
    toast.success(fn === "ride_pause" ? "Corsa in pausa" : "Corsa ripresa")
  }

  const endRide = async () => {
    if (!ride) return
    setEnding(true)
    const { data, error } = await supabase.rpc("ride_end", {
      p_ride_id: ride.id,
      p_lat: currentPosition.lat,
      p_lng: currentPosition.lng,
      p_apply_credits: applyCredits,
    })
    setEnding(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Corsa terminata")
    if (data) navigate(`/ride/${ride.id}/summary`)
  }

  if (loading) {
    return (
      <AppShell title="Corsa" back="/nearby">
        <div className="flex justify-center py-10"><Spinner /></div>
      </AppShell>
    )
  }
  if (!ride || !vehicle) {
    return (
      <AppShell title="Corsa" back="/nearby">
        <TonalCard className="text-center py-10">
          <p className="text-[var(--muted-foreground)]">Nessuna corsa attiva.</p>
          <Button onClick={() => navigate("/nearby")} className="mt-5 h-12 rounded-2xl btn-primary-grad px-6 font-bold">
            Trova un mezzo
          </Button>
        </TonalCard>
      </AppShell>
    )
  }

  return (
    <AppShell title="Corsa attiva" hideTabs>
      <TonalCard className="text-center">
        <div className="flex justify-center mb-3">
          <VehicleEmoji type={VehicleIconType(vehicle)} />
        </div>
        <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code}</p>
        <h2 className="text-xl font-extrabold mt-1">{VehicleDisplayName(vehicle)}</h2>
        <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{VehicleModelLabel(vehicle)}</p>
        <div className="mt-3 flex justify-center">
          <StatusChip status={ride.pause_status === "paused" ? "paused" : "in_use"} />
        </div>
      </TonalCard>

      <TonalCard className="mt-4 ghost-active text-center">
        <p className="label-sm text-[var(--muted-foreground)]">DURATA ADDEBITATA</p>
        <p className="text-6xl font-extrabold tabular-nums leading-none mt-3 font-display">
          {String(hh).padStart(2, "0")}:{String(mm).padStart(2, "0")}:{String(ss).padStart(2, "0")}
        </p>
        <p className="mt-3 text-sm text-[var(--muted-foreground)]">In corso dalle {new Date(ride.started_at).toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit" })}</p>
        <div className="mt-4 grid grid-cols-2 gap-2 text-left">
          <DurationField label="Totale" value={`${String(totalHh).padStart(2, "0")}:${String(totalMm).padStart(2, "0")}:${String(totalSs).padStart(2, "0")}`} />
          <DurationField label="In pausa" value={`${Math.floor(totalPaused / 60)} min ${totalPaused % 60} sec`} warning={totalPaused > 0} />
        </div>
      </TonalCard>

      <TonalCard className="mt-4">
        <p className="label-sm text-[var(--muted-foreground)]">TARIFFA {VehicleCategoryLabel(vehicle).toUpperCase()}</p>
        <p className="mt-2 text-sm font-bold text-[var(--primary)]">{VehiclePricingLabel(vehicle)}</p>
      </TonalCard>

      <TonalCard className="mt-4">
        <p className="label-sm text-[var(--muted-foreground)]">POSIZIONE SIMULATA</p>
        <p className="font-mono text-sm mt-2">
          {currentPosition.lat.toFixed(5)}, {currentPosition.lng.toFixed(5)}
        </p>
      </TonalCard>

      <TonalCard className="mt-4">
        <label className="flex cursor-pointer items-start gap-3">
          <Checkbox
            checked={applyCredits}
            disabled={Number(wallet?.credit_amount ?? 0) <= 0}
            onCheckedChange={(value) => setApplyCredits(!!value)}
            className="mt-1 size-5"
          />
          <span className="min-w-0">
            <span className="block font-bold">Applica credito promozionale</span>
            <span className="mt-1 block text-sm text-[var(--muted-foreground)]">
              Disponibile: {Number(wallet?.credit_amount ?? 0).toFixed(2)} EUR. Lo sconto non superera il costo della corsa.
            </span>
          </span>
        </label>
      </TonalCard>

      <Button onClick={togglePause} disabled={ending} className="mt-6 w-full h-14 rounded-2xl bg-[var(--surface-high)] text-[var(--primary)] hover:bg-[var(--surface-high)]/90 font-bold text-base">
        {ride.pause_status === "paused" ? (
          <>
            <Play className="size-5" /> Riprendi corsa
          </>
        ) : (
          <>
            <Pause className="size-5" /> Metti in pausa
          </>
        )}
      </Button>

      <Button onClick={endRide} disabled={ending} className="mt-3 w-full h-14 rounded-2xl bg-[var(--destructive)] text-white hover:bg-[var(--destructive)]/90 font-bold text-base">
        {ending ? <Spinner /> : (
          <>
            <Square className="size-4 fill-white" /> Termina corsa
          </>
        )}
      </Button>
    </AppShell>
  )
}

function DurationField({ label, value, warning }: { label: string; value: string; warning?: boolean }) {
  return (
    <div className="rounded-2xl bg-[var(--surface-low)] p-3">
      <p className="label-sm text-[var(--muted-foreground)]">{label}</p>
      <p className={warning ? "mt-1 text-sm font-bold text-[var(--warning)]" : "mt-1 text-sm font-bold"}>{value}</p>
    </div>
  )
}
