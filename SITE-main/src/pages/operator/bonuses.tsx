import { useEffect, useMemo, useState } from "react"
import { toast } from "sonner"
import { Gift, Plus, RefreshCw } from "lucide-react"
import { TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type OperatorParkingBonus } from "@/lib/supabase"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

type CompletedRideRow = {
  id: string
  ended_at: string | null
  final_cost: number | null
  user?: { display_name: string; email: string } | null
  vehicle?: { code: string; display_name?: string | null; brand?: string | null; model?: string | null } | null
}

function normalizeBonuses(data: unknown): OperatorParkingBonus[] {
  return ((data as OperatorParkingBonus[] | null) ?? []).map((bonus) => ({
    ...bonus,
    points: Number(bonus.points ?? 0),
    amount: Number(bonus.amount ?? 0),
  }))
}

function rideLabel(ride: CompletedRideRow) {
  const vehicleName = ride.vehicle?.display_name || [ride.vehicle?.brand, ride.vehicle?.model].filter(Boolean).join(" ") || ride.vehicle?.code || "Mezzo"
  const userName = ride.user?.display_name || ride.user?.email || "Utente"
  return `${ride.id.slice(0, 8).toUpperCase()} - ${vehicleName} - ${userName}`
}

export function OperatorBonusesPage() {
  const [bonuses, setBonuses] = useState<OperatorParkingBonus[]>([])
  const [rides, setRides] = useState<CompletedRideRow[]>([])
  const [rideId, setRideId] = useState("")
  const [points, setPoints] = useState("5")
  const [reason, setReason] = useState("Bonus parcheggio corretto")
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const load = async () => {
    setLoading(true)
    const [bonusQ, ridesQ] = await Promise.all([
      supabase.rpc("operator_parking_bonuses"),
      supabase
        .from("rides")
        .select("id, ended_at, final_cost, user:profiles(display_name,email), vehicle:vehicles(code,display_name,brand,model)")
        .eq("status", "completed")
        .order("ended_at", { ascending: false })
        .limit(25),
    ])
    const bonusRows = normalizeBonuses(bonusQ.data)
    const rideRows = (ridesQ.data as unknown as CompletedRideRow[]) ?? []
    setBonuses(bonusRows)
    setRides(rideRows)
    setRideId((current) => current || rideRows[0]?.id || "")
    setLoading(false)
  }

  useEffect(() => { void load() }, [])

  const totalPoints = useMemo(() => bonuses.reduce((sum, bonus) => sum + bonus.points, 0), [bonuses])
  const uniqueUsers = useMemo(() => new Set(bonuses.map((bonus) => bonus.user_id)).size, [bonuses])

  const assignBonus = async () => {
    if (!rideId) {
      toast.error("Seleziona una corsa completata")
      return
    }
    const parsedPoints = Number(points)
    if (!Number.isFinite(parsedPoints) || parsedPoints <= 0) {
      toast.error("Punti bonus non validi")
      return
    }
    setSaving(true)
    const { error } = await supabase.rpc("operator_parking_bonus_award", {
      p_ride_id: rideId,
      p_points: Math.round(parsedPoints),
      p_reason: reason.trim() || "Bonus parcheggio corretto",
    })
    setSaving(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Bonus assegnato")
    void load()
  }

  return (
    <>
      <PageHeader
        title="Bonus parcheggio"
        subtitle="Verifica e assegna punti promozionali per parcheggio appropriato a fine corsa."
        action={<Button onClick={load} disabled={loading} className="h-11 rounded-2xl btn-primary-grad px-5 font-bold">{loading ? <Spinner /> : (<><RefreshCw className="size-4" /> Aggiorna</>)}</Button>}
      />
      <PageBody>
        <div className="mb-6 grid gap-4 md:grid-cols-3">
          <StatCard label="BONUS" value={bonuses.length} tone="primary" />
          <StatCard label="PUNTI ASSEGNATI" value={totalPoints} />
          <StatCard label="UTENTI PREMIATI" value={uniqueUsers} />
        </div>

        <div className="grid gap-5 xl:grid-cols-[420px_1fr]">
          <TonalCard>
            <div className="flex items-start gap-3">
              <div className="flex size-12 items-center justify-center rounded-2xl bg-[var(--secondary-container)] text-[var(--secondary-foreground)]">
                <Gift className="size-5" />
              </div>
              <div>
                <p className="label-sm text-[var(--muted-foreground)]">ASSEGNAZIONE MANUALE</p>
                <h2 className="mt-1 text-xl font-bold">Bonus su corsa completata</h2>
              </div>
            </div>

            <div className="mt-5 flex flex-col gap-3">
              <Select value={rideId} onValueChange={setRideId}>
                <SelectTrigger className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]"><SelectValue placeholder="Seleziona corsa" /></SelectTrigger>
                <SelectContent>
                  {rides.map((ride) => (
                    <SelectItem key={ride.id} value={ride.id}>{rideLabel(ride)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Input value={points} onChange={(event) => setPoints(event.target.value.replace(/\D/g, ""))} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]" placeholder="Punti" />
              <Input value={reason} onChange={(event) => setReason(event.target.value)} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]" placeholder="Motivo" />
              <Button onClick={assignBonus} disabled={saving || rides.length === 0} className="h-12 rounded-2xl btn-primary-grad font-bold">
                {saving ? <Spinner /> : (<><Plus className="size-4" /> Assegna bonus</>)}
              </Button>
            </div>
          </TonalCard>

          {loading ? (
            <div className="flex justify-center py-10"><Spinner /></div>
          ) : bonuses.length === 0 ? (
            <TonalCard className="py-10 text-center text-[var(--muted-foreground)]">Nessun bonus parcheggio assegnato.</TonalCard>
          ) : (
            <div className="flex flex-col gap-3">
              {bonuses.map((bonus) => (
                <TonalCard key={bonus.id}>
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0">
                      <p className="label-sm text-[var(--muted-foreground)]">BONUS PARCHEGGIO</p>
                      <h3 className="mt-1 text-lg font-bold">{bonus.user_name}</h3>
                      <p className="mt-1 text-sm text-[var(--muted-foreground)]">{bonus.user_email}</p>
                      <p className="mt-2 text-sm font-semibold">{bonus.description}</p>
                      <p className="mt-2 font-mono text-xs text-[var(--muted-foreground)]">
                        Corsa {bonus.ride_id?.slice(0, 8).toUpperCase()} - {bonus.vehicle_code || "Mezzo n/d"}
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-3xl font-extrabold text-[var(--primary)]">+{bonus.points}</p>
                      <p className="mt-1 text-xs font-semibold text-[var(--muted-foreground)]">{new Date(bonus.created_at).toLocaleDateString("it-IT")}</p>
                    </div>
                  </div>
                </TonalCard>
              ))}
            </div>
          )}
        </div>
      </PageBody>
    </>
  )
}
