import { useEffect, useState } from "react"
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

export function PaymentMethodsPage() {
  const { session } = useAuth()
  const [methods, setMethods] = useState<PaymentMethod[]>([])
  const [loading, setLoading] = useState(true)
  const [adding, setAdding] = useState(false)
  const [type, setType] = useState<"card" | "paypal" | "apple_pay">("card")
  const [last4, setLast4] = useState("")
  const [isDefault, setIsDefault] = useState(true)

  const load = async () => {
    setLoading(true)
    const { data } = await supabase.from("payment_methods").select("*").order("created_at", { ascending: false })
    setMethods((data as PaymentMethod[]) ?? [])
    setLoading(false)
  }
  useEffect(() => { load() }, [])

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (last4.length !== 4 || !/^\d+$/.test(last4)) {
      toast.error("Inserisci 4 cifre")
      return
    }
    setAdding(true)
    const { error } = await supabase.from("payment_methods").insert({
      user_id: session!.user.id,
      type, last4, is_default: isDefault,
    })
    setAdding(false)
    if (error) { toast.error(error.message); return }
    toast.success("Metodo aggiunto")
    setLast4("")
    setIsDefault(true)
    load()
  }

  const remove = async (id: string) => {
    const { error } = await supabase.from("payment_methods").delete().eq("id", id)
    if (error) { toast.error(error.message); return }
    toast.success("Metodo eliminato")
    load()
  }

  return (
    <AppShell title="Pagamenti">
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
                  <p className="font-bold">{TYPE_LABEL[m.type]} •••• {m.last4}</p>
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
            {adding ? <Spinner /> : (<><Plus className="size-4" /> Aggiungi metodo</>)}
          </Button>
        </form>
      </TonalCard>
    </AppShell>
  )
}
