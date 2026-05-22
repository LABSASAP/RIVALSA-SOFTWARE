import { useEffect, useState } from "react"
import { TriangleAlert } from "lucide-react"
import { StatusChip } from "@/components/vehicle-card"
import { Spinner } from "@/components/ui/spinner"
import { supabase } from "@/lib/supabase"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

type Row = {
  id: string
  status: string
  created_at: string
  expires_at: string
  converted_ride_id: string | null
  user: { display_name: string; email: string } | null
  vehicle: { code: string; type: string; status: string } | null
}

export function OperatorReservationsPage() {
  const [rows, setRows] = useState<Row[]>([])
  const [now, setNow] = useState(Date.now())
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true)
    await supabase.rpc("reservation_expire_stale")
    const { data } = await supabase
      .from("reservations")
      .select("id, status, created_at, expires_at, converted_ride_id, user:profiles(display_name,email), vehicle:vehicles(code,type,status)")
      .eq("status", "active")
      .order("expires_at", { ascending: true })
    setRows((data as unknown as Row[]) ?? [])
    setLoading(false)
  }

  useEffect(() => { load() }, [])
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])

  const isAnomalous = (r: Row) => {
    const remaining = new Date(r.expires_at).getTime() - now
    const nearExpiry = remaining < 2 * 60 * 1000 && remaining > 0
    const stillReserved = r.vehicle?.status === "reserved"
    const noRide = !r.converted_ride_id
    return (nearExpiry && stillReserved && noRide) || remaining <= 0
  }

  const anomalyCount = rows.filter(isAnomalous).length

  return (
    <>
      <PageHeader title="Prenotazioni attive" subtitle="Monitora le prenotazioni in corso e individua anomalie." />
      <PageBody>
        <div className="grid grid-cols-3 gap-4 mb-6">
          <StatCard label="ATTIVE" value={rows.length} tone="primary" />
          <StatCard label="ANOMALE" value={anomalyCount} tone="warning" />
          <StatCard label="AGGIORNATO" value={new Date(now).toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit", second: "2-digit" })} />
        </div>

        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : rows.length === 0 ? (
          <div className="rounded-3xl bg-[var(--surface-lowest)] p-10 text-center text-[var(--muted-foreground)]">
            Nessuna prenotazione attiva.
          </div>
        ) : (
          <div className="rounded-3xl bg-[var(--surface-lowest)] p-2">
            <table className="w-full">
              <thead>
                <tr className="text-left">
                  {["ID", "Utente", "Mezzo", "Tipo", "Stato mezzo", "Creata", "Scade", "Residuo", ""].map((h) => (
                    <th key={h} className="px-4 py-3 label-sm text-[var(--muted-foreground)]">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => {
                  const remaining = Math.max(0, Math.floor((new Date(r.expires_at).getTime() - now) / 1000))
                  const mm = Math.floor(remaining / 60)
                  const ss = remaining % 60
                  const anomalous = isAnomalous(r)
                  return (
                    <tr key={r.id} className={i % 2 === 1 ? "bg-[var(--surface-low)]" : ""}>
                      <td className="px-4 py-4 font-mono text-xs">{r.id.slice(0, 8).toUpperCase()}</td>
                      <td className="px-4 py-4">{r.user?.display_name}</td>
                      <td className="px-4 py-4 font-semibold">{r.vehicle?.code}</td>
                      <td className="px-4 py-4 capitalize">{r.vehicle?.type}</td>
                      <td className="px-4 py-4"><StatusChip status={r.vehicle?.status ?? "—"} /></td>
                      <td className="px-4 py-4 text-sm text-[var(--muted-foreground)] whitespace-nowrap">
                        {new Date(r.created_at).toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit" })}
                      </td>
                      <td className="px-4 py-4 text-sm text-[var(--muted-foreground)] whitespace-nowrap">
                        {new Date(r.expires_at).toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit" })}
                      </td>
                      <td className="px-4 py-4 font-mono tabular-nums font-bold">
                        {String(mm).padStart(2, "0")}:{String(ss).padStart(2, "0")}
                      </td>
                      <td className="px-4 py-4">
                        {anomalous && (
                          <span className="inline-flex items-center gap-1 rounded-full bg-[#fff3d6] text-[var(--warning)] px-2.5 py-1 text-[0.6875rem] font-bold uppercase">
                            <TriangleAlert className="size-3" /> Anomala
                          </span>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </PageBody>
    </>
  )
}
