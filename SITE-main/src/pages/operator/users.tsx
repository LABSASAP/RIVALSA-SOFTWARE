import { useEffect, useState } from "react"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { StatusChip } from "@/components/vehicle-card"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { supabase, type Profile } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

type Action = { user: Profile; status: "active" | "suspended" | "blocked" } | null

export function OperatorUsersPage() {
  const { profile: me } = useAuth()
  const [users, setUsers] = useState<Profile[]>([])
  const [loading, setLoading] = useState(true)
  const [pending, setPending] = useState<Action>(null)

  const load = async () => {
    setLoading(true)
    const { data } = await supabase.from("profiles").select("*").order("role", { ascending: false }).order("created_at", { ascending: true })
    setUsers((data as Profile[]) ?? [])
    setLoading(false)
  }
  useEffect(() => { load() }, [])

  const apply = async () => {
    if (!pending) return
    const { error } = await supabase.rpc("update_user_status", { p_user_id: pending.user.id, p_status: pending.status })
    if (error) { toast.error(error.message); setPending(null); return }
    toast.success("Stato utente aggiornato")
    setPending(null)
    load()
  }

  const counts = {
    active: users.filter((u) => u.status === "active" && u.role === "user").length,
    suspended: users.filter((u) => u.status === "suspended").length,
    blocked: users.filter((u) => u.status === "blocked").length,
  }

  return (
    <>
      <PageHeader title="Gestione utenti" subtitle="Sospendi, blocca o riattiva account utente." />
      <PageBody>
        <div className="grid grid-cols-3 gap-4 mb-6">
          <StatCard label="ATTIVI" value={counts.active} tone="primary" />
          <StatCard label="SOSPESI" value={counts.suspended} tone="warning" />
          <StatCard label="BLOCCATI" value={counts.blocked} tone="danger" />
        </div>

        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : (
          <div className="rounded-3xl bg-[var(--surface-lowest)] p-2">
            <table className="w-full">
              <thead>
                <tr className="text-left">
                  {["Nome", "Email", "Ruolo", "Stato", "Azioni"].map((h) => (
                    <th key={h} className="px-4 py-3 label-sm text-[var(--muted-foreground)]">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {users.map((u, i) => {
                  const isSelf = u.id === me?.id
                  return (
                    <tr key={u.id} className={i % 2 === 1 ? "bg-[var(--surface-low)]" : ""}>
                      <td className="px-4 py-4 font-semibold">{u.display_name}{isSelf && <span className="ml-2 text-xs text-[var(--muted-foreground)]">(tu)</span>}</td>
                      <td className="px-4 py-4 text-[var(--muted-foreground)]">{u.email}</td>
                      <td className="px-4 py-4 capitalize"><span className="inline-flex rounded-full bg-[var(--surface-low)] px-2.5 py-1 text-xs font-bold">{u.role}</span></td>
                      <td className="px-4 py-4"><StatusChip status={u.status} /></td>
                      <td className="px-4 py-4">
                        <div className="flex gap-2">
                          <Button size="sm" variant="ghost" disabled={isSelf || u.status === "active"} onClick={() => setPending({ user: u, status: "active" })} className="rounded-xl bg-[var(--secondary-container)] text-[var(--secondary-foreground)] hover:bg-[var(--secondary-container)]/80">Attiva</Button>
                          <Button size="sm" variant="ghost" disabled={isSelf || u.status === "suspended"} onClick={() => setPending({ user: u, status: "suspended" })} className="rounded-xl bg-[#fff3d6] text-[var(--warning)] hover:bg-[#fff3d6]/80">Sospendi</Button>
                          <Button size="sm" variant="ghost" disabled={isSelf || u.status === "blocked"} onClick={() => setPending({ user: u, status: "blocked" })} className="rounded-xl bg-[#ffe5e5] text-[var(--destructive)] hover:bg-[#ffe5e5]/80">Blocca</Button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        <AlertDialog open={!!pending} onOpenChange={(o) => !o && setPending(null)}>
          <AlertDialogContent className="rounded-3xl">
            <AlertDialogHeader>
              <AlertDialogTitle>Confermi cambio stato?</AlertDialogTitle>
              <AlertDialogDescription>
                {pending && (
                  <>L'utente <span className="font-semibold">{pending.user.display_name}</span> diventerà <span className="font-semibold">{pending.status}</span>.</>
                )}
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel className="rounded-2xl">Annulla</AlertDialogCancel>
              <AlertDialogAction onClick={apply} className="rounded-2xl btn-primary-grad">Conferma</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </PageBody>
    </>
  )
}
