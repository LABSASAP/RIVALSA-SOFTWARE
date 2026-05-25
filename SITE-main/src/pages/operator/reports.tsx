import { useEffect, useState } from "react"
import { toast } from "sonner"
import { StatusChip, VehicleCategoryLabel, VehicleDisplayName } from "@/components/vehicle-card"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type VehicleCategory, type VehicleType } from "@/lib/supabase"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

type Row = {
  id: string
  issue_type: string
  description: string
  status: "open" | "in_progress" | "resolved"
  created_at: string
  vehicle: { code: string; type: VehicleType; vehicle_type?: VehicleType | null; category?: VehicleCategory | null; brand?: string | null; model?: string | null; display_name?: string | null } | null
  user: { display_name: string; email: string } | null
}

export function OperatorReportsPage() {
  const [filter, setFilter] = useState<"open" | "in_progress" | "resolved" | "all">("open")
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(true)
  const [counts, setCounts] = useState({ open: 0, in_progress: 0, resolved: 0 })

  const load = async () => {
    setLoading(true)
    let q = supabase
      .from("vehicle_reports")
      .select("id, issue_type, description, status, created_at, vehicle:vehicles(code, type, vehicle_type, category, brand, model, display_name), user:profiles(display_name, email)")
      .order("created_at", { ascending: false })
    if (filter !== "all") q = q.eq("status", filter)
    const { data } = await q
    setRows((data as unknown as Row[]) ?? [])
    const { data: all } = await supabase.from("vehicle_reports").select("status")
    const c = { open: 0, in_progress: 0, resolved: 0 }
    ;(all ?? []).forEach((r: { status: string }) => { c[r.status as keyof typeof c]++ })
    setCounts(c)
    setLoading(false)
  }

  useEffect(() => { load() }, [filter])

  const updateStatus = async (id: string, status: string) => {
    const { error } = await supabase.from("vehicle_reports").update({ status, updated_at: new Date().toISOString() }).eq("id", id)
    if (error) { toast.error(error.message); return }
    toast.success("Stato aggiornato")
    load()
  }

  return (
    <>
      <PageHeader title="Report malfunzionamenti" subtitle="Visualizza, filtra e aggiorna lo stato delle segnalazioni." />
      <PageBody>
        <div className="grid grid-cols-3 gap-4 mb-6">
          <StatCard label="APERTI" value={counts.open} tone="danger" />
          <StatCard label="IN LAVORAZIONE" value={counts.in_progress} tone="warning" />
          <StatCard label="RISOLTI" value={counts.resolved} tone="primary" />
        </div>

        <Tabs value={filter} onValueChange={(v) => setFilter(v as typeof filter)}>
          <TabsList className="bg-[var(--surface-low)] rounded-2xl p-1 h-11 mb-5">
            <TabsTrigger value="open" className="rounded-xl px-4 data-[state=active]:bg-white">Aperti</TabsTrigger>
            <TabsTrigger value="in_progress" className="rounded-xl px-4 data-[state=active]:bg-white">In lavorazione</TabsTrigger>
            <TabsTrigger value="resolved" className="rounded-xl px-4 data-[state=active]:bg-white">Risolti</TabsTrigger>
            <TabsTrigger value="all" className="rounded-xl px-4 data-[state=active]:bg-white">Tutti</TabsTrigger>
          </TabsList>
        </Tabs>

        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : rows.length === 0 ? (
          <div className="rounded-3xl bg-[var(--surface-lowest)] p-10 text-center text-[var(--muted-foreground)]">
            Nessuna segnalazione.
          </div>
        ) : (
          <div className="rounded-3xl bg-[var(--surface-lowest)] p-2">
            <table className="w-full">
              <thead>
                <tr className="text-left">
                  {["ID", "Mezzo", "Utente", "Tipo", "Descrizione", "Stato", "Creato", "Azione"].map((h) => (
                    <th key={h} className="px-4 py-3 label-sm text-[var(--muted-foreground)]">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={r.id} className={i % 2 === 1 ? "bg-[var(--surface-low)]" : ""}>
                    <td className="px-4 py-4 font-mono text-xs">{r.id.slice(0, 8).toUpperCase()}</td>
                    <td className="px-4 py-4">
                      <p className="font-semibold">{r.vehicle?.code}</p>
                      {r.vehicle && (
                        <p className="text-xs text-[var(--muted-foreground)]">
                          {VehicleDisplayName(r.vehicle)} - {VehicleCategoryLabel(r.vehicle)}
                        </p>
                      )}
                    </td>
                    <td className="px-4 py-4">{r.user?.display_name}</td>
                    <td className="px-4 py-4 capitalize">{r.issue_type}</td>
                    <td className="px-4 py-4 max-w-xs truncate text-[var(--muted-foreground)]">{r.description}</td>
                    <td className="px-4 py-4"><StatusChip status={r.status} /></td>
                    <td className="px-4 py-4 text-sm text-[var(--muted-foreground)] whitespace-nowrap">
                      {new Date(r.created_at).toLocaleDateString("it-IT")}
                    </td>
                    <td className="px-4 py-4">
                      <Select value={r.status} onValueChange={(v) => updateStatus(r.id, v)}>
                        <SelectTrigger className="h-9 w-40 rounded-xl bg-[var(--surface-low)] border-0 text-xs font-semibold">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="open">Aperto</SelectItem>
                          <SelectItem value="in_progress">In lavorazione</SelectItem>
                          <SelectItem value="resolved">Risolto</SelectItem>
                        </SelectContent>
                      </Select>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </PageBody>
    </>
  )
}
