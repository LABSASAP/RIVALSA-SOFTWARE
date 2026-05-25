import { useState } from "react"
import { Search } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Spinner } from "@/components/ui/spinner"
import { TonalCard, VehicleCategoryLabel, formatVehicleMoney } from "@/components/vehicle-card"
import { supabase, type RideEndDetails } from "@/lib/supabase"
import { parsePointEwkbHex } from "@/lib/postgis"
import { PageBody, PageHeader } from "@/pages/operator/_shared"

type Result = {
  ride_id: string
  vehicle_code: string
  vehicle_type: string
  vehicle_display_name: string
  vehicle_category: string
  unlock_fee: number
  price_per_minute: number
  ended_at: string
  duration_minutes: number
  final_cost: number
  end_lat: number
  end_lng: number
}

export function OperatorEndLocationPage() {
  const [query, setQuery] = useState("")
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<Result | null>(null)
  const [error, setError] = useState("")

  const search = async () => {
    setError(""); setResult(null)
    if (!query) return
    setLoading(true)
    const isFull = query.length === 36
    let q = supabase
      .from("rides")
      .select("id")
      .eq("status", "completed")
      .limit(1)
    q = isFull ? q.eq("id", query) : q.like("id", `${query.toLowerCase()}%`)
    const { data: ride } = await q.maybeSingle()
    if (!ride) {
      setLoading(false); setError("Corsa non trovata o non ancora completata."); return
    }
    const { data: details } = await supabase.rpc("ride_end_details", { p_ride_id: (ride as { id: string }).id })
    const detail = ((details as RideEndDetails[] | null) ?? [])[0]
    if (detail) {
      setResult({
        ride_id: detail.ride_id,
        vehicle_code: detail.vehicle_code,
        vehicle_type: detail.vehicle_type,
        vehicle_display_name: detail.vehicle_display_name,
        vehicle_category: detail.vehicle_category,
        unlock_fee: detail.unlock_fee,
        price_per_minute: detail.price_per_minute,
        ended_at: detail.ended_at,
        duration_minutes: detail.duration_minutes ?? 0,
        final_cost: detail.final_cost ?? 0,
        end_lat: detail.end_lat ?? 0,
        end_lng: detail.end_lng ?? 0,
      })
      setLoading(false)
      return
    }

    const fallback = await supabase
      .from("rides")
      .select("id, ended_at, duration_minutes, final_cost, end_location, vehicle:vehicles(code, type, display_name, category, unlock_fee, price_per_minute)")
      .eq("id", (ride as { id: string }).id)
      .maybeSingle()

    const data = fallback.data as {
      id: string
      ended_at: string
      duration_minutes: number
      final_cost: number
      end_location?: string
      vehicle: { code: string; type: string; display_name?: string | null; category?: string | null; unlock_fee?: number | null; price_per_minute?: number | null }
    } | null

    const point = parsePointEwkbHex(data?.end_location)
    if (!data || !point) {
      setLoading(false); setError("Dettagli corsa non disponibili."); return
    }

    setResult({
      ride_id: data.id,
      vehicle_code: data.vehicle.code,
      vehicle_type: data.vehicle.type,
      vehicle_display_name: data.vehicle.display_name ?? data.vehicle.code,
      vehicle_category: data.vehicle.category ?? data.vehicle.type,
      unlock_fee: data.vehicle.unlock_fee ?? 0,
      price_per_minute: data.vehicle.price_per_minute ?? 0,
      ended_at: data.ended_at,
      duration_minutes: data.duration_minutes ?? 0,
      final_cost: data.final_cost ?? 0,
      end_lat: point.lat,
      end_lng: point.lng,
    })
    setLoading(false)
  }

  return (
    <>
      <PageHeader title="Posizione fine corsa" subtitle="Cerca una corsa per ID e visualizza la posizione finale del mezzo." />
      <PageBody>
        <TonalCard className="mb-6">
          <div className="flex gap-3">
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Inserisci ID corsa (anche prime 8 cifre)"
              className="h-12 rounded-2xl bg-[var(--surface-low)] border-0 font-mono"
              onKeyDown={(e) => e.key === "Enter" && search()}
            />
            <Button onClick={search} disabled={loading} className="h-12 rounded-2xl btn-primary-grad px-6 font-bold">
              {loading ? <Spinner /> : (<><Search className="size-4" /> Cerca</>)}
            </Button>
          </div>
          {error && <p className="mt-3 text-sm text-[var(--destructive)]">{error}</p>}
        </TonalCard>

        {result && (
          <TonalCard>
            <p className="label-sm text-[var(--muted-foreground)]">RISULTATO</p>
            <h2 className="text-2xl font-extrabold mt-1">{result.vehicle_display_name}</h2>
            <p className="text-sm text-[var(--muted-foreground)] mt-1">
              {result.vehicle_code} - {VehicleCategoryLabel({ type: result.vehicle_type as "bike" | "scooter" | "car", category: result.vehicle_category })}
            </p>
            <div className="grid grid-cols-2 gap-4 mt-5">
              <Field label="ID corsa" value={result.ride_id.slice(0, 8).toUpperCase()} mono />
              <Field label="Fine corsa" value={new Date(result.ended_at).toLocaleString("it-IT")} />
              <Field label="Durata" value={`${result.duration_minutes} min`} />
              <Field label="Costo" value={formatVehicleMoney(result.final_cost)} />
              <Field label="Tariffa" value={`${formatVehicleMoney(result.unlock_fee)} sblocco - ${formatVehicleMoney(result.price_per_minute)}/min`} />
              <Field label="Latitudine finale" value={result.end_lat.toFixed(6)} mono />
              <Field label="Longitudine finale" value={result.end_lng.toFixed(6)} mono />
            </div>
          </TonalCard>
        )}
      </PageBody>
    </>
  )
}

function Field({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="rounded-2xl bg-[var(--surface-low)] p-4">
      <p className="label-sm text-[var(--muted-foreground)]">{label.toUpperCase()}</p>
      <p className={mono ? "font-mono text-sm font-semibold mt-1" : "font-semibold mt-1"}>{value}</p>
    </div>
  )
}
