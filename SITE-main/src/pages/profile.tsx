import { Link, useNavigate } from "react-router-dom"
import { CreditCard, LogOut, ShieldCheck, UserRound } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { StatusChip, TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { useAuth } from "@/lib/auth-context"

const ROLE_LABEL: Record<string, string> = {
  user: "Utente",
  operator: "Operatore",
}

export function ProfilePage() {
  const navigate = useNavigate()
  const { profile, signOut } = useAuth()

  return (
    <AppShell title="Profilo">
      <TonalCard className="text-center">
        <div className="mx-auto flex size-16 items-center justify-center rounded-3xl btn-primary-grad">
          <UserRound className="size-8 text-white" />
        </div>
        <p className="label-sm mt-4 text-[var(--muted-foreground)]">ACCOUNT</p>
        <h2 className="mt-1 text-2xl font-extrabold">{profile?.display_name ?? "Profilo utente"}</h2>
        <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{profile?.email ?? "n/d"}</p>
      </TonalCard>

      <div className="mt-4 grid grid-cols-2 gap-3">
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">RUOLO</p>
          <div className="mt-3 flex items-center gap-2">
            <ShieldCheck className="size-5 text-[var(--primary)]" />
            <p className="font-bold">{profile ? ROLE_LABEL[profile.role] ?? profile.role : "n/d"}</p>
          </div>
        </TonalCard>
        <TonalCard>
          <p className="label-sm text-[var(--muted-foreground)]">STATO</p>
          <div className="mt-3">
            <StatusChip status={profile?.status ?? "n/d"} />
          </div>
        </TonalCard>
      </div>

      <TonalCard className="mt-4">
        <div className="flex items-center gap-3">
          <div className="flex size-12 items-center justify-center rounded-2xl bg-[var(--surface-low)]">
            <CreditCard className="size-5 text-[var(--primary)]" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="font-bold">Metodi di pagamento</p>
            <p className="mt-0.5 text-sm text-[var(--muted-foreground)]">
              Gestisci carte e metodi salvati.
            </p>
          </div>
          <Button asChild className="h-10 rounded-2xl btn-primary-grad px-4 font-bold">
            <Link to="/payment-methods">Apri</Link>
          </Button>
        </div>
      </TonalCard>

      <Button
        variant="ghost"
        onClick={async () => {
          await signOut()
          navigate("/login")
        }}
        className="mt-6 h-12 w-full rounded-2xl bg-[#ffe5e5] font-bold text-[var(--destructive)] hover:bg-[#ffe5e5]/80"
      >
        <LogOut className="size-5" /> Logout
      </Button>
    </AppShell>
  )
}
