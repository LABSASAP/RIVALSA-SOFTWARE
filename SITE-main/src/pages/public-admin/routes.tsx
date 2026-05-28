import { useEffect, useMemo, useState } from "react"
import { MapContainer, Polyline, TileLayer, Tooltip, useMap } from "react-leaflet"
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip as ChartTooltip, XAxis, YAxis } from "recharts"
import { ArrowUpDown, CalendarDays, RefreshCw } from "lucide-react"
import { TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type PublicAdminRoute, type VehicleCategory } from "@/lib/supabase"
import { PublicAdminBody, PublicAdminHeader } from "@/pages/public-admin/layout"

type SortKey = "ride_count" | "avg_distance_km" | "avg_duration_minutes" | "avg_cost"

const DEFAULT_CENTER = { lat: 41.1175, lng: 16.872 }
const DEFAULT_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
const DEFAULT_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
const tileUrl = (import.meta.env.VITE_MAP_TILE_URL as string | undefined)?.trim() || (import.meta.env.DEV ? DEFAULT_TILE_URL : "")
const tileAttribution = (import.meta.env.VITE_MAP_ATTRIBUTION as string | undefined)?.trim() || DEFAULT_ATTRIBUTION

const CATEGORY_LABEL: Record<VehicleCategory, string> = {
  bike: "Bike",
  scooter: "Scooter",
  economy_car: "Auto economy",
  standard_car: "Auto standard",
  premium_car: "Auto premium",
}

function startOfDay(value: string) {
  return value ? new Date(`${value}T00:00:00`).toISOString() : null
}

function endOfDay(value: string) {
  return value ? new Date(`${value}T23:59:59`).toISOString() : null
}

function normalizeRoutes(data: unknown): PublicAdminRoute[] {
  return ((data as PublicAdminRoute[] | null) ?? []).map((route) => ({
    ...route,
    ride_count: Number(route.ride_count ?? 0),
    start_lat: Number(route.start_lat ?? 0),
    start_lng: Number(route.start_lng ?? 0),
    end_lat: Number(route.end_lat ?? 0),
    end_lng: Number(route.end_lng ?? 0),
    avg_duration_minutes: Number(route.avg_duration_minutes ?? 0),
    avg_cost: Number(route.avg_cost ?? 0),
    avg_distance_km: Number(route.avg_distance_km ?? 0),
  }))
}

export function PublicAdminRoutesPage() {
  const [routes, setRoutes] = useState<PublicAdminRoute[]>([])
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [sortKey, setSortKey] = useState<SortKey>("ride_count")
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true)
    const { data } = await supabase.rpc("public_admin_top_routes", {
      p_from: startOfDay(from),
      p_to: endOfDay(to),
    })
    setRoutes(normalizeRoutes(data))
    setLoading(false)
  }

  useEffect(() => { void load() }, [])

  const sortedRoutes = useMemo(
    () => [...routes].sort((a, b) => Number(b[sortKey] ?? 0) - Number(a[sortKey] ?? 0)),
    [routes, sortKey]
  )

  return (
    <>
      <PublicAdminHeader
        title="Tratte piu utilizzate"
        subtitle="Cluster approssimati da start/end location delle corse completate."
        action={
          <div className="flex flex-wrap items-end gap-2">
            <div className="flex items-center gap-2 rounded-2xl bg-[var(--surface-low)] px-3 py-2">
              <CalendarDays className="size-4 text-[var(--primary)]" />
              <Input type="date" value={from} onChange={(event) => setFrom(event.target.value)} className="h-9 w-36 border-0 bg-transparent p-0 text-sm shadow-none" />
            </div>
            <div className="rounded-2xl bg-[var(--surface-low)] px-3 py-2">
              <Input type="date" value={to} onChange={(event) => setTo(event.target.value)} className="h-9 w-36 border-0 bg-transparent p-0 text-sm shadow-none" />
            </div>
            <Button onClick={load} disabled={loading} className="h-12 rounded-2xl btn-primary-grad font-bold">
              {loading ? <Spinner /> : (<><RefreshCw className="size-4" /> Aggiorna</>)}
            </Button>
          </div>
        }
      />
      <PublicAdminBody>
        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : routes.length === 0 ? (
          <TonalCard className="py-10 text-center text-[var(--muted-foreground)]">Nessuna corsa completata disponibile nel periodo.</TonalCard>
        ) : (
          <div className="grid gap-5">
            <div className="grid gap-5 xl:grid-cols-[1.15fr_0.85fr]">
              <TonalCard>
                <p className="label-sm text-[var(--muted-foreground)]">CLASSIFICA TRATTE</p>
                <div className="mt-4 h-96">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={sortedRoutes.slice(0, 10)} layout="vertical" margin={{ left: 24, right: 24 }}>
                      <CartesianGrid stroke="rgba(25,28,29,0.08)" horizontal={false} />
                      <XAxis type="number" allowDecimals={false} tickLine={false} axisLine={false} />
                      <YAxis type="category" dataKey="route_label" width={150} tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                      <ChartTooltip />
                      <Bar dataKey="ride_count" fill="#0040a1" radius={[0, 8, 8, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </TonalCard>

              <TonalCard className="p-0">
                <div className="px-5 pt-5">
                  <p className="label-sm text-[var(--muted-foreground)]">MAPPA TRATTE</p>
                  <h2 className="mt-1 text-xl font-bold">Origine e destinazione</h2>
                </div>
                <div className="mt-4 h-96 overflow-hidden rounded-b-3xl bg-[var(--surface-low)]">
                  <RoutesMap routes={sortedRoutes} />
                </div>
              </TonalCard>
            </div>

            <TonalCard>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="label-sm text-[var(--muted-foreground)]">AP.05</p>
                  <h2 className="mt-1 text-xl font-bold">Tabella tratte</h2>
                </div>
                <div className="flex flex-wrap gap-2">
                  <SortButton label="Corse" active={sortKey === "ride_count"} onClick={() => setSortKey("ride_count")} />
                  <SortButton label="Distanza" active={sortKey === "avg_distance_km"} onClick={() => setSortKey("avg_distance_km")} />
                  <SortButton label="Durata" active={sortKey === "avg_duration_minutes"} onClick={() => setSortKey("avg_duration_minutes")} />
                  <SortButton label="Costo" active={sortKey === "avg_cost"} onClick={() => setSortKey("avg_cost")} />
                </div>
              </div>

              <div className="mt-4 flex flex-col gap-2">
                {sortedRoutes.map((route, index) => (
                  <div key={route.route_label} className="grid gap-3 rounded-2xl bg-[var(--surface-low)] p-4 xl:grid-cols-[80px_1fr_130px_130px_130px_130px] xl:items-center">
                    <div>
                      <p className="label-sm text-[var(--muted-foreground)]">Rank</p>
                      <p className="mt-1 text-xl font-extrabold text-[var(--primary)]">#{index + 1}</p>
                    </div>
                    <div className="min-w-0">
                      <p className="label-sm text-[var(--muted-foreground)]">Tratta</p>
                      <p className="mt-1 font-mono text-sm font-semibold">{route.route_label}</p>
                      <p className="mt-1 text-xs font-semibold text-[var(--muted-foreground)]">
                        Categoria prevalente: {CATEGORY_LABEL[route.dominant_category] ?? route.dominant_category}
                      </p>
                    </div>
                    <RouteField label="Corse" value={String(route.ride_count)} />
                    <RouteField label="Distanza" value={`${route.avg_distance_km.toFixed(2)} km`} />
                    <RouteField label="Durata" value={`${route.avg_duration_minutes.toFixed(1)} min`} />
                    <RouteField label="Costo" value={`${route.avg_cost.toFixed(2)} EUR`} />
                  </div>
                ))}
              </div>
            </TonalCard>
          </div>
        )}
      </PublicAdminBody>
    </>
  )
}

function RoutesMap({ routes }: { routes: PublicAdminRoute[] }) {
  const center = useMemo(() => {
    const first = routes[0]
    if (!first) return DEFAULT_CENTER
    return {
      lat: (first.start_lat + first.end_lat) / 2,
      lng: (first.start_lng + first.end_lng) / 2,
    }
  }, [routes])
  const maxCount = Math.max(...routes.map((route) => route.ride_count), 1)

  return (
    <MapContainer center={[center.lat, center.lng]} zoom={13} className="h-full w-full" scrollWheelZoom>
      {tileUrl && <TileLayer attribution={tileAttribution} url={tileUrl} />}
      <RoutesCenterSync center={center} />
      {routes.slice(0, 12).map((route, index) => (
        <Polyline
          key={`${route.route_label}-${index}`}
          positions={[[route.start_lat, route.start_lng], [route.end_lat, route.end_lng]]}
          pathOptions={{
            color: index === 0 ? "#0040a1" : "#2e7d32",
            opacity: 0.45 + (route.ride_count / maxCount) * 0.45,
            weight: 3 + (route.ride_count / maxCount) * 6,
          }}
        >
          <Tooltip direction="top" opacity={0.95}>
            {route.route_label} - {route.ride_count} corse
          </Tooltip>
        </Polyline>
      ))}
    </MapContainer>
  )
}

function RoutesCenterSync({ center }: { center: { lat: number; lng: number } }) {
  const map = useMap()

  useEffect(() => {
    map.setView([center.lat, center.lng], Math.max(map.getZoom(), 13), { animate: true })
  }, [center.lat, center.lng, map])

  return null
}

function SortButton({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <Button
      type="button"
      variant="ghost"
      onClick={onClick}
      className={active ? "rounded-2xl bg-[var(--surface-high)] font-bold text-[var(--primary)]" : "rounded-2xl bg-[var(--surface-low)] font-bold text-[var(--muted-foreground)]"}
    >
      <ArrowUpDown className="size-4" /> {label}
    </Button>
  )
}

function RouteField({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-[var(--surface-lowest)] p-3">
      <p className="label-sm text-[var(--muted-foreground)]">{label}</p>
      <p className="mt-1 text-sm font-bold">{value}</p>
    </div>
  )
}
