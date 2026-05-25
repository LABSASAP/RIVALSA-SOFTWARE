import { useEffect, useState } from "react"
import { Link, useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { CreditCard, Plus, Trash2 } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type PaymentMethod } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"

const TYPE_LABEL: Record<string, string> = {
  card: "Carta di credito",
  paypal: "PayPal",
  apple_pay: "Apple Pay",
}

type RequestError = {
  code?: string
  message: string
  status?: number
}

export function PaymentMethodsPage() {
  const navigate = useNavigate()
  const { session, signOut } = useAuth()
  const userId = session?.user.id
  const [methods, setMethods] = useState<PaymentMethod[]>([])
  const [loading, setLoading] = useState(true)
  const [adding, setAdding] = useState(false)
  const [type, setType] = useState<"card" | "paypal" | "apple_pay">("card")
  const [last4, setLast4] = useState("")
  const [isDefault, setIsDefault] = useState(true)

  const redirectToLogin = () => {
    void signOut().finally(() => navigate("/login"))
  }

  const handleRequestError = (fallback: string, error: RequestError) => {
    const authError =
      error.status === 401 ||
      error.status === 403 ||
      error.code === "PGRST301" ||
      /jwt|unauthorized|forbidden|permission|not authorized/i.test(error.message)

    if (authError) {
      toast.error("Sessione scaduta o non autorizzata. Accedi di nuovo.")
      redirectToLogin()
      return
    }

    toast.error(error.message || fallback)
  }

  const load = async () => {
    if (!userId) {
      setMethods([])
      setLoading(false)
      return
    }

    setLoading(true)
    const { data, error } = await supabase
      .from("payment_methods")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })

    if (error) {
      setMethods([])
      setLoading(false)
      handleRequestError("Non e stato possibile caricare i metodi di pagamento.", error)
      return
    }

    setMethods((data as PaymentMethod[]) ?? [])
    setLoading(false)
  }

  useEffect(() => { void load() }, [userId])

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!userId) {
      toast.error("Sessione mancante. Accedi per salvare un metodo di pagamento.")
      navigate("/login")
      return
    }
    if (last4.length !== 4 || !/^\d+$/.test(last4)) {
      toast.error("Inserisci 4 cifre")
      return
    }
    setAdding(true)
    const { error } = await supabase.from("payment_methods").insert({
      user_id: userId,
      type, last4, is_default: isDefault,
    })
    setAdding(false)
    if (error) {
      handleRequestError("Non e stato possibile salvare il metodo di pagamento.", error)
      return
    }
    toast.success("Metodo aggiunto")
    setLast4("")
    setIsDefault(true)
    void load()
  }

  const remove = async (id: string) => {
    if (!userId) {
      toast.error("Sessione mancante. Accedi per gestire i metodi di pagamento.")
      navigate("/login")
      return
    }

    const { error } = await supabase
      .from("payment_methods")
      .delete()
      .eq("id", id)
      .eq("user_id", userId)

    if (error) {
      handleRequestError("Non e stato possibile eliminare il metodo di pagamento.", error)
      return
    }
    toast.success("Metodo eliminato")
    void load()
  }

  if (!userId) {
    return (
      <AppShell title="Metodi di pagamento">
        <TonalCard className="text-center py-8">
          <CreditCard className="size-7 mx-auto text-[var(--muted-foreground)]" />
          <h2 className="mt-3 text-lg font-bold">Sessione richiesta</h2>
          <p className="mt-2 text-sm leading-relaxed text-[var(--muted-foreground)]">
            Accedi per visualizzare e gestire i tuoi metodi di pagamento.
          </p>
          <Button asChild className="mt-5 h-12 rounded-2xl btn-primary-grad px-5 font-bold">
            <Link to="/login">Vai al login</Link>
          </Button>
        </TonalCard>
      </AppShell>
    )
  }

  return (
    <AppShell title="Metodi di pagamento">
      <div className="mb-3 px-1">
        <h2 className="text-lg font-bold">Metodi salvati</h2>
        <p className="text-sm text-[var(--muted-foreground)]">Usati per addebito automatico a fine corsa.</p>
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : methods.length === 0 ? (
        <TonalCard className="text-center py-8">
          <CreditCard className="size-7 mx-auto text-[var(--muted-foreground)]" />
          <p className="mt-2 text-sm text-[var(--muted-foreground)]">Nessun metodo salvato.</p>
        </TonalCard>
      ) : (
        <div className="flex flex-col gap-3">
          {methods.map((m) => (
            <TonalCard key={m.id}>
              <div className="flex items-center gap-3">
                <div className="size-12 rounded-2xl bg-[var(--surface-low)] flex items-center justify-center">
                  <CreditCard className="size-5 text-[var(--primary)]" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-bold">{TYPE_LABEL[m.type]} **** {m.last4}</p>
                  {m.is_default && (
                    <span className="inline-flex mt-1 items-center rounded-full bg-[var(--secondary-container)] text-[var(--secondary-foreground)] px-2 py-0.5 text-[0.6875rem] font-bold uppercase tracking-wide">
                      Predefinito
                    </span>
                  )}
                </div>
                <Button onClick={() => remove(m.id)} variant="ghost" size="icon-sm" className="rounded-full text-[var(--destructive)] hover:bg-[#ffe5e5]">
                  <Trash2 className="size-4" />
                </Button>
              </div>
            </TonalCard>
          ))}
        </div>
      )}

      <div className="mt-6 px-1 mb-3">
        <h2 className="text-lg font-bold">Aggiungi metodo</h2>
      </div>
      <TonalCard>
        <form onSubmit={submit} className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label className="label-sm text-[var(--muted-foreground)]">Tipo</Label>
            <Select value={type} onValueChange={(v) => setType(v as typeof type)}>
              <SelectTrigger className="h-12 rounded-2xl bg-[var(--surface-low)] border-0">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="card">Carta di credito</SelectItem>
                <SelectItem value="paypal">PayPal</SelectItem>
                <SelectItem value="apple_pay">Apple Pay</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label className="label-sm text-[var(--muted-foreground)]">Ultime 4 cifre</Label>
            <Input value={last4} onChange={(e) => setLast4(e.target.value.replace(/\D/g, "").slice(0, 4))} maxLength={4} placeholder="1234" className="h-12 rounded-2xl bg-[var(--surface-low)] border-0 font-mono" />
          </div>
          <label className="flex items-center gap-2.5 mt-1 cursor-pointer">
            <Checkbox checked={isDefault} onCheckedChange={(v) => setIsDefault(!!v)} className="size-5" />
            <span className="text-sm font-medium">Imposta come predefinito</span>
          </label>
          <Button type="submit" disabled={adding} className="h-12 mt-2 rounded-2xl btn-primary-grad font-bold">
            {adding ? <Spinner /> : (<><Plus className="size-4" /> Salva metodo</>)}
          </Button>
        </form>
      </TonalCard>
    </AppShell>
  )
}
