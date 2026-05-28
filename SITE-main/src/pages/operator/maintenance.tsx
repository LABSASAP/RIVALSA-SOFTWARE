import { useEffect, useMemo, useState } from "react"
import { toast } from "sonner"
import { RefreshCw, Wrench } from "lucide-react"
import { BatteryBar, StatusChip, TonalCard, VehicleCategoryLabel, VehicleDisplayName } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type OperatorMaintenanceVehicle, type VehicleCategory } from "@/lib/supabase"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

type PriorityFilter = "all" | OperatorMaintenanceVehicle["priority"]
type CategoryFilter = "all" | VehicleCategory

const PRIORITY_LABEL: Record<OperatorMaintenanceVehicle["priority"], string> = {
  critical: "Critica",
  high: "Alta",
  medium: "Media",
  low: "Bassa",
}

function normalizeRows(data: unknown): OperatorMaintenanceVehicle[] {
  return ((data as OperatorMaintenanceVehicle[] | null) ?? []).map((vehicle) => ({
    ...vehicle,
    battery_level: Number(vehicle.battery_level ?? 0),
    lat: Number(vehicle.lat ?? 0),
    lng: Number(vehicle.lng ?? 0),
    open_reports_count: Number(vehicle.open_reports_count ?? 0),
    days_since_maintenance: vehicle.days_since_maintenance == null ? null : Number(vehicle.days_since_maintenance),
    reasons: Array.isArray(vehicle.reasons) ? vehicle.reasons : [],
  }))
}

export function OperatorMaintenancePage() {
  const [vehicles, setVehicles] = useState<OperatorMaintenanceVehicle[]>([])
  const [notes, setNotes] = useState<Record<string, string>>({})
  const [priorityFilter, setPriorityFilter] = useState<PriorityFilter>("all")
  const [categoryFilter, setCategoryFilter] = useState<CategoryFilter>("all")
  const [loading, setLoading] = useState(true)
  const [pendingId, setPendingId] = useState<string | null>(null)

  const load = async () => {
    setLoading(true)
    const { data } = await supabase.rpc("operator_maintenance_vehicles")
    const rows = normalizeRows(data)
    setVehicles(rows)
    setNotes(Object.fromEntries(rows.map((vehicle) => [vehicle.id, vehicle.operator_notes ?? ""])))
    setLoading(false)
  }

  useEffect(() => { void load() }, [])

  const filteredVehicles = useMemo(() => {
    return vehicles.filter((vehicle) => {
      const priorityOk = priorityFilter === "all" || vehicle.priority === priorityFilter
      const categoryOk = categoryFilter === "all" || vehicle.category === categoryFilter
      return priorityOk && categoryOk
    })
  }, [categoryFilter, priorityFilter, vehicles])

  const counts = useMemo(() => ({
    critical: vehicles.filter((vehicle) => vehicle.priority === "critical").length,
    high: vehicles.filter((vehicle) => vehicle.priority === "high").length,
    medium: vehicles.filter((vehicle) => vehicle.priority === "medium").length,
    lowBattery: vehicles.filter((vehicle) => vehicle.battery_level < 25).length,
  }), [vehicles])

  const updateMaintenance = async (vehicle: OperatorMaintenanceVehicle, status: "available" | "maintenance") => {
    setPendingId(vehicle.id)
    const { error } = await supabase.rpc("operator_update_vehicle_maintenance", {
      p_vehicle_id: vehicle.id,
      p_status: status,
      p_notes: notes[vehicle.id] ?? "",
    })
    setPendingId(null)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Manutenzione aggiornata")
    void load()
  }

  return (
    <>
      <PageHeader
        title="Manutenzione"
        subtitle="Report dei mezzi che richiedono controllo tecnico, con priorita e motivazioni."
        action={<Button onClick={load} disabled={loading} className="h-11 rounded-2xl btn-primary-grad px-5 font-bold">{loading ? <Spinner /> : (<><RefreshCw className="size-4" /> Aggiorna</>)}</Button>}
      />
      <PageBody>
        <div className="mb-6 grid gap-4 md:grid-cols-4">
          <StatCard label="CRITICI" value={counts.critical} tone="danger" />
          <StatCard label="PRIORITA ALTA" value={counts.high} tone="warning" />
          <StatCard label="PRIORITA MEDIA" value={counts.medium} />
          <StatCard label="BATTERIA <25%" value={counts.lowBattery} tone="danger" />
        </div>

        <div className="mb-5 flex flex-wrap gap-3">
          <Select value={priorityFilter} onValueChange={(value) => setPriorityFilter(value as PriorityFilter)}>
            <SelectTrigger className="h-12 w-56 rounded-2xl border-0 bg-[var(--surface-lowest)]"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tutte le priorita</SelectItem>
              <SelectItem value="critical">Critica</SelectItem>
              <SelectItem value="high">Alta</SelectItem>
              <SelectItem value="medium">Media</SelectItem>
              <SelectItem value="low">Bassa</SelectItem>
            </SelectContent>
          </Select>
          <Select value={categoryFilter} onValueChange={(value) => setCategoryFilter(value as CategoryFilter)}>
            <SelectTrigger className="h-12 w-56 rounded-2xl border-0 bg-[var(--surface-lowest)]"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tutte le categorie</SelectItem>
              <SelectItem value="bike">Bike</SelectItem>
              <SelectItem value="scooter">Scooter</SelectItem>
              <SelectItem value="economy_car">Auto economy</SelectItem>
              <SelectItem value="standard_car">Auto standard</SelectItem>
              <SelectItem value="premium_car">Auto premium</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : filteredVehicles.length === 0 ? (
          <TonalCard className="py-10 text-center text-[var(--muted-foreground)]">Nessun mezzo nel filtro selezionato.</TonalCard>
        ) : (
          <div className="grid gap-4 xl:grid-cols-2">
            {filteredVehicles.map((vehicle) => (
              <TonalCard key={vehicle.id} className={vehicle.priority === "critical" ? "bg-[#ffe5e5]" : undefined}>
                <div className="flex items-start gap-4">
                  <div className="flex size-12 items-center justify-center rounded-2xl bg-white/70 text-[var(--primary)]">
                    <Wrench className="size-5" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code} - {VehicleCategoryLabel(vehicle)}</p>
                        <h3 className="mt-1 font-bold">{VehicleDisplayName(vehicle)}</h3>
                      </div>
                      <div className="flex flex-col items-end gap-2">
                        <StatusChip status={vehicle.is_remote_locked ? "remote_locked" : vehicle.status} />
                        <StatusChip status={vehicle.priority === "high" ? "warning" : vehicle.priority === "critical" ? "critical" : "ok"} />
                      </div>
                    </div>

                    <div className="mt-3 grid gap-2 sm:grid-cols-2">
                      <Field label="Priorita" value={PRIORITY_LABEL[vehicle.priority]} />
                      <Field label="Segnalazioni" value={String(vehicle.open_reports_count)} />
                      <Field label="Ultima manutenzione" value={vehicle.last_maintenance_at ? new Date(vehicle.last_maintenance_at).toLocaleDateString("it-IT") : "Mai registrata"} />
                      <Field label="Posizione" value={`${vehicle.lat.toFixed(5)}, ${vehicle.lng.toFixed(5)}`} mono />
                    </div>

                    <div className="mt-3 flex flex-wrap items-center gap-3">
                      <BatteryBar level={vehicle.battery_level} />
                      {vehicle.days_since_maintenance != null && (
                        <span className="text-xs font-semibold text-[var(--muted-foreground)]">{vehicle.days_since_maintenance} giorni dall'ultima manutenzione</span>
                      )}
                    </div>

                    <div className="mt-3 flex flex-wrap gap-2">
                      {(vehicle.reasons.length ? vehicle.reasons : ["Nessuna anomalia critica"]).map((reason) => (
                        <span key={reason} className="rounded-full bg-white/70 px-3 py-1 text-xs font-bold text-[var(--foreground)]">{reason}</span>
                      ))}
                    </div>

                    <Textarea
                      value={notes[vehicle.id] ?? ""}
                      onChange={(event) => setNotes((current) => ({ ...current, [vehicle.id]: event.target.value }))}
                      rows={3}
                      className="mt-4 resize-none rounded-2xl border-0 bg-white/75"
                      placeholder="Note operatore..."
                    />
                    <div className="mt-3 flex flex-wrap gap-2">
                      <Button
                        onClick={() => updateMaintenance(vehicle, "maintenance")}
                        disabled={pendingId === vehicle.id}
                        variant="ghost"
                        className="rounded-2xl bg-[#fff3d6] text-[var(--warning)]"
                      >
                        {pendingId === vehicle.id ? <Spinner /> : "Segna manutenzione"}
                      </Button>
                      <Button
                        onClick={() => updateMaintenance(vehicle, "available")}
                        disabled={pendingId === vehicle.id || vehicle.is_remote_locked}
                        className="rounded-2xl btn-primary-grad"
                      >
                        Rimetti disponibile
                      </Button>
                    </div>
                  </div>
                </div>
              </TonalCard>
            ))}
          </div>
        )}
      </PageBody>
    </>
  )
}

function Field({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="rounded-2xl bg-white/70 p-3">
      <p className="label-sm text-[var(--muted-foreground)]">{label}</p>
      <p className={mono ? "mt-1 font-mono text-xs font-semibold" : "mt-1 text-sm font-semibold"}>{value}</p>
    </div>
  )
}
