import { useEffect, useMemo, useState } from "react"
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"
import { CalendarDays, RefreshCw } from "lucide-react"
import { TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Spinner } from "@/components/ui/spinner"
import {
  supabase,
  type PublicAdminFleetStatus,
  type PublicAdminMobilityReport,
  type PublicAdminVehicleUsage,
  type VehicleCategory,
} from "@/lib/supabase"
import { StatCard } from "@/pages/operator/_shared"
import { PublicAdminBody, PublicAdminHeader } from "@/pages/public-admin/layout"

const COLORS = ["#0040a1", "#2e7d32", "#b26a00", "#c62828", "#0056d2"]

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

function money(value: number | null | undefined) {
  return `${Number(value ?? 0).toFixed(2)} EUR`
}

function pct(value: number | null | undefined) {
  return `${Number(value ?? 0).toFixed(1)}%`
}

function normalizeMobility(data: unknown): PublicAdminMobilityReport | null {
  if (!data) return null
  const raw = data as PublicAdminMobilityReport
  return {
    period: raw.period ?? { from: null, to: null },
    rides_total: Number(raw.rides_total ?? 0),
    rides_active: Number(raw.rides_active ?? 0),
    rides_completed: Number(raw.rides_completed ?? 0),
    revenue_total: Number(raw.revenue_total ?? 0),
    avg_duration_minutes: Number(raw.avg_duration_minutes ?? 0),
    avg_distance_km: Number(raw.avg_distance_km ?? 0),
    avg_cost: Number(raw.avg_cost ?? 0),
    active_users: Number(raw.active_users ?? 0),
    vehicles_used: Number(raw.vehicles_used ?? 0),
    hourly_usage: (raw.hourly_usage ?? []).map((item) => ({ ...item, ride_count: Number(item.ride_count ?? 0) })),
    category_usage: (raw.category_usage ?? []).map((item) => ({
      ...item,
      ride_count: Number(item.ride_count ?? 0),
      percentage: Number(item.percentage ?? 0),
    })),
    daily_rides: (raw.daily_rides ?? []).map((item) => ({ ...item, ride_count: Number(item.ride_count ?? 0) })),
  }
}

function normalizeFleet(data: unknown): PublicAdminFleetStatus | null {
  if (!data) return null
  const raw = data as PublicAdminFleetStatus
  return {
    fleet_total: Number(raw.fleet_total ?? 0),
    available_count: Number(raw.available_count ?? 0),
    in_use_count: Number(raw.in_use_count ?? 0),
    reserved_count: Number(raw.reserved_count ?? 0),
    maintenance_count: Number(raw.maintenance_count ?? 0),
    remote_locked_count: Number(raw.remote_locked_count ?? 0),
    avg_battery_level: Number(raw.avg_battery_level ?? 0),
    low_battery_percentage: Number(raw.low_battery_percentage ?? 0),
    operational_percentage: Number(raw.operational_percentage ?? 0),
    open_reports_count: Number(raw.open_reports_count ?? 0),
    fleet_by_status: (raw.fleet_by_status ?? []).map((item) => ({ ...item, count: Number(item.count ?? 0) })),
    battery_by_category: (raw.battery_by_category ?? []).map((item) => ({
      ...item,
      avg_battery_level: Number(item.avg_battery_level ?? 0),
      vehicle_count: Number(item.vehicle_count ?? 0),
    })),
  }
}

function normalizeUsage(data: unknown): PublicAdminVehicleUsage[] {
  return ((data as PublicAdminVehicleUsage[] | null) ?? []).map((item) => ({
    ...item,
    rides_count: Number(item.rides_count ?? 0),
    percentage: Number(item.percentage ?? 0),
  }))
}

export function PublicAdminDashboardPage() {
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [mobility, setMobility] = useState<PublicAdminMobilityReport | null>(null)
  const [fleet, setFleet] = useState<PublicAdminFleetStatus | null>(null)
  const [usage, setUsage] = useState<PublicAdminVehicleUsage[]>([])
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true)
    const params = { p_from: startOfDay(from), p_to: endOfDay(to) }
    const [mobilityQ, usageQ, fleetQ] = await Promise.all([
      supabase.rpc("public_admin_mobility_report", params),
      supabase.rpc("public_admin_vehicle_usage_frequency", params),
      supabase.rpc("public_admin_fleet_status"),
    ])
    setMobility(normalizeMobility(mobilityQ.data))
    setUsage(normalizeUsage(usageQ.data))
    setFleet(normalizeFleet(fleetQ.data))
    setLoading(false)
  }

  useEffect(() => { void load() }, [])

  const usageChart = useMemo(
    () => usage.map((item) => ({
      label: CATEGORY_LABEL[item.category] ?? item.category,
      corse: item.rides_count,
      percentuale: item.percentage,
    })),
    [usage]
  )

  const categoryChart = useMemo(
    () => (mobility?.category_usage ?? []).map((item) => ({
      label: CATEGORY_LABEL[item.category] ?? item.category,
      corse: item.ride_count,
      percentuale: item.percentage,
    })),
    [mobility]
  )

  return (
    <>
      <PublicAdminHeader
        title="Report mobilita"
        subtitle="Frequenza mezzi, mobilita aggregata e stato operativo flotta."
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
        ) : !mobility || !fleet ? (
          <TonalCard className="py-10 text-center text-[var(--muted-foreground)]">Report non disponibile.</TonalCard>
        ) : (
          <div className="flex flex-col gap-5">
            <section className="grid gap-4 lg:grid-cols-4 xl:grid-cols-8">
              <StatCard label="CORSE" value={mobility.rides_total} tone="primary" />
              <StatCard label="COMPLETATE" value={mobility.rides_completed} />
              <StatCard label="DURATA MEDIA" value={`${mobility.avg_duration_minutes.toFixed(1)} min`} />
              <StatCard label="DISTANZA MEDIA" value={`${mobility.avg_distance_km.toFixed(2)} km`} />
              <StatCard label="COSTO MEDIO" value={money(mobility.avg_cost)} />
              <StatCard label="UTENTI ATTIVI" value={mobility.active_users} />
              <StatCard label="MEZZI USATI" value={mobility.vehicles_used} />
              <StatCard label="RICAVI MOCK" value={money(mobility.revenue_total)} />
            </section>

            <section className="grid gap-5 xl:grid-cols-[1.2fr_0.8fr]">
              <TonalCard>
                <SectionTitle eyebrow="AP.01" title="Frequenza utilizzo per categoria" />
                <div className="mt-4 h-80">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={usageChart}>
                      <CartesianGrid stroke="rgba(25,28,29,0.08)" vertical={false} />
                      <XAxis dataKey="label" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                      <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} allowDecimals={false} />
                      <Tooltip />
                      <Bar dataKey="corse" fill="#0040a1" radius={[8, 8, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </TonalCard>

              <TonalCard>
                <SectionTitle eyebrow="DATI" title="Ripartizione utilizzo" />
                <div className="mt-4 flex flex-col gap-2">
                  {usage.map((item) => (
                    <DataRow
                      key={`${item.vehicle_type}-${item.category}`}
                      label={CATEGORY_LABEL[item.category] ?? item.category}
                      value={`${item.rides_count} corse`}
                      meta={pct(item.percentage)}
                    />
                  ))}
                </div>
              </TonalCard>
            </section>

            <section className="grid gap-5 xl:grid-cols-3">
              <TonalCard className="xl:col-span-2">
                <SectionTitle eyebrow="AP.02" title="Corse nel tempo" />
                <div className="mt-4 h-80">
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={mobility.daily_rides}>
                      <CartesianGrid stroke="rgba(25,28,29,0.08)" vertical={false} />
                      <XAxis dataKey="day" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                      <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} allowDecimals={false} />
                      <Tooltip />
                      <Line type="monotone" dataKey="ride_count" stroke="#0040a1" strokeWidth={3} dot={{ r: 4 }} />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              </TonalCard>

              <TonalCard>
                <SectionTitle eyebrow="FASCE ORARIE" title="Ore piu usate" />
                <div className="mt-4 h-80">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={mobility.hourly_usage}>
                      <CartesianGrid stroke="rgba(25,28,29,0.08)" vertical={false} />
                      <XAxis dataKey="hour" tick={{ fontSize: 10 }} tickLine={false} axisLine={false} />
                      <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} allowDecimals={false} />
                      <Tooltip />
                      <Bar dataKey="ride_count" fill="#2e7d32" radius={[8, 8, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </TonalCard>
            </section>

            <section className="grid gap-5 xl:grid-cols-[0.9fr_1.1fr]">
              <TonalCard>
                <SectionTitle eyebrow="CATEGORIE" title="Mezzi piu usati" />
                <div className="mt-4 h-72">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={categoryChart} dataKey="corse" nameKey="label" innerRadius={52} outerRadius={96} paddingAngle={4}>
                        {categoryChart.map((entry, index) => (
                          <Cell key={entry.label} fill={COLORS[index % COLORS.length]} />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
              </TonalCard>

              <TonalCard>
                <SectionTitle eyebrow="AP.03" title="Indicatori stato flotta" />
                <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                  <MiniMetric label="Disponibili" value={fleet.available_count} />
                  <MiniMetric label="In uso" value={fleet.in_use_count} />
                  <MiniMetric label="Prenotati" value={fleet.reserved_count} />
                  <MiniMetric label="Manutenzione" value={fleet.maintenance_count} tone="danger" />
                  <MiniMetric label="Blocco remoto" value={fleet.remote_locked_count} tone="danger" />
                  <MiniMetric label="Batteria media" value={pct(fleet.avg_battery_level)} />
                  <MiniMetric label="Batteria bassa" value={pct(fleet.low_battery_percentage)} tone="warning" />
                  <MiniMetric label="Operativi" value={pct(fleet.operational_percentage)} />
                  <MiniMetric label="Segnalazioni aperte" value={fleet.open_reports_count} tone="warning" />
                </div>
              </TonalCard>
            </section>

            <section className="grid gap-5 xl:grid-cols-2">
              <TonalCard>
                <SectionTitle eyebrow="STATO" title="Distribuzione flotta" />
                <div className="mt-4 h-72">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={fleet.fleet_by_status} dataKey="count" nameKey="status" innerRadius={48} outerRadius={94} paddingAngle={4}>
                        {fleet.fleet_by_status.map((entry, index) => (
                          <Cell key={entry.status} fill={COLORS[index % COLORS.length]} />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
              </TonalCard>

              <TonalCard>
                <SectionTitle eyebrow="BATTERIA" title="Media per categoria" />
                <div className="mt-4 h-72">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={fleet.battery_by_category.map((item) => ({
                      label: CATEGORY_LABEL[item.category] ?? item.category,
                      batteria: item.avg_battery_level,
                    }))}>
                      <CartesianGrid stroke="rgba(25,28,29,0.08)" vertical={false} />
                      <XAxis dataKey="label" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                      <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} domain={[0, 100]} />
                      <Tooltip />
                      <Bar dataKey="batteria" fill="#b26a00" radius={[8, 8, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </TonalCard>
            </section>
          </div>
        )}
      </PublicAdminBody>
    </>
  )
}

function SectionTitle({ eyebrow, title }: { eyebrow: string; title: string }) {
  return (
    <div>
      <p className="label-sm text-[var(--muted-foreground)]">{eyebrow}</p>
      <h2 className="mt-1 text-xl font-bold">{title}</h2>
    </div>
  )
}

function DataRow({ label, value, meta }: { label: string; value: string; meta: string }) {
  return (
    <div className="grid grid-cols-[1fr_auto_auto] items-center gap-3 rounded-2xl bg-[var(--surface-low)] px-4 py-3">
      <span className="min-w-0 text-sm font-bold">{label}</span>
      <span className="text-sm text-[var(--muted-foreground)]">{value}</span>
      <span className="rounded-full bg-[var(--surface-high)] px-3 py-1 text-xs font-bold text-[var(--primary)]">{meta}</span>
    </div>
  )
}

function MiniMetric({ label, value, tone }: { label: string; value: string | number; tone?: "warning" | "danger" }) {
  return (
    <div className="rounded-2xl bg-[var(--surface-low)] p-4">
      <p className="label-sm text-[var(--muted-foreground)]">{label}</p>
      <p className={tone === "danger" ? "mt-1 text-2xl font-extrabold text-[var(--destructive)]" : tone === "warning" ? "mt-1 text-2xl font-extrabold text-[var(--warning)]" : "mt-1 text-2xl font-extrabold text-[var(--primary)]"}>
        {value}
      </p>
    </div>
  )
}
