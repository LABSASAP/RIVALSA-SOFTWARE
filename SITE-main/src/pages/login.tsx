import { useState } from "react"
import { useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { supabase } from "@/lib/supabase"
import { Spinner } from "@/components/ui/spinner"

export function LoginPage() {
  const navigate = useNavigate()
  const [tab, setTab] = useState<"login" | "register">("login")
  const [loading, setLoading] = useState(false)
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [displayName, setDisplayName] = useState("")

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) {
      toast.error("Credenziali non valide")
      return
    }
    toast.success("Accesso eseguito")
    navigate("/")
  }

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { display_name: displayName || email.split("@")[0] } },
    })
    setLoading(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Registrazione completata")
    navigate("/")
  }

  return (
    <div className="app-shell flex flex-col px-6">
      <div className="pt-16 pb-10 flex flex-col items-center text-center">
        <div className="size-16 rounded-3xl btn-primary-grad flex items-center justify-center font-display text-3xl font-extrabold mb-5">
          Z
        </div>
        <p className="label-sm text-[var(--muted-foreground)]">URBAN MOBILITY</p>
        <h1 className="text-4xl font-extrabold tracking-tight mt-1">ZooSmart</h1>
        <p className="text-[var(--muted-foreground)] mt-2 max-w-xs">
          Trova, prenota e sblocca il tuo mezzo in pochi secondi.
        </p>
      </div>

      <div className="rounded-3xl bg-[var(--surface-lowest)] p-5 shadow-[0_12px_32px_rgba(25,28,29,0.04)]">
        <Tabs value={tab} onValueChange={(v) => setTab(v as "login" | "register")}>
          <TabsList className="w-full bg-[var(--surface-low)] rounded-2xl p-1 h-11">
            <TabsTrigger value="login" className="rounded-xl data-[state=active]:bg-white data-[state=active]:text-[var(--primary)]">
              Accedi
            </TabsTrigger>
            <TabsTrigger value="register" className="rounded-xl data-[state=active]:bg-white data-[state=active]:text-[var(--primary)]">
              Registrati
            </TabsTrigger>
          </TabsList>

          <TabsContent value="login" className="mt-5">
            <form onSubmit={handleLogin} className="flex flex-col gap-3">
              <FormField label="Email">
                <Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="h-12 rounded-2xl bg-[var(--surface-low)] border-0" placeholder="email@esempio.it" />
              </FormField>
              <FormField label="Password">
                <Input type="password" required value={password} onChange={(e) => setPassword(e.target.value)} className="h-12 rounded-2xl bg-[var(--surface-low)] border-0" placeholder="••••••••" />
              </FormField>
              <Button type="submit" disabled={loading} className="h-12 mt-2 rounded-2xl btn-primary-grad font-bold text-base">
                {loading ? <Spinner /> : "Accedi"}
              </Button>
            </form>
          </TabsContent>

          <TabsContent value="register" className="mt-5">
            <form onSubmit={handleRegister} className="flex flex-col gap-3">
              <FormField label="Nome visualizzato">
                <Input required value={displayName} onChange={(e) => setDisplayName(e.target.value)} className="h-12 rounded-2xl bg-[var(--surface-low)] border-0" placeholder="Mario Rossi" />
              </FormField>
              <FormField label="Email">
                <Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="h-12 rounded-2xl bg-[var(--surface-low)] border-0" placeholder="email@esempio.it" />
              </FormField>
              <FormField label="Password">
                <Input type="password" required minLength={6} value={password} onChange={(e) => setPassword(e.target.value)} className="h-12 rounded-2xl bg-[var(--surface-low)] border-0" placeholder="Min. 6 caratteri" />
              </FormField>
              <Button type="submit" disabled={loading} className="h-12 mt-2 rounded-2xl btn-primary-grad font-bold text-base">
                {loading ? <Spinner /> : "Crea account"}
              </Button>
            </form>
          </TabsContent>
        </Tabs>
      </div>

      <div className="mt-6 rounded-2xl bg-[var(--surface-low)] p-4 text-xs text-[var(--muted-foreground)] leading-relaxed">
        <p className="font-bold text-[var(--foreground)] mb-1">Setup locale</p>
        <p>1. Registra un account utente normale da questa schermata.</p>
        <p>2. Registra un secondo account e promuovilo a <span className="font-mono">operator</span> da Supabase.</p>
        <p>3. Se l&apos;utente esisteva gia, esegui il backfill e la migration bootstrap prima di accedere.</p>
      </div>
    </div>
  )
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label className="label-sm text-[var(--muted-foreground)]">{label}</Label>
      {children}
    </div>
  )
}
