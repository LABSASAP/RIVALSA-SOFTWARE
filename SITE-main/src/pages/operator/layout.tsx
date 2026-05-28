import { Link, NavLink, Outlet, useNavigate } from "react-router-dom"
import { Activity, ClipboardList, Gift, Headphones, LogOut, MapPin, Timer, Truck, Users, Wrench } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuth } from "@/lib/auth-context"
import { cn } from "@/lib/utils"

const NAV = [
  { to: "/operator", label: "Report Malfunzionamenti", icon: ClipboardList, end: true },
  { to: "/operator/reservations", label: "Prenotazioni Attive", icon: Timer },
  { to: "/operator/support", label: "Chat Supporto", icon: Headphones },
  { to: "/operator/fleet", label: "Distribuzione Flotta", icon: Truck },
  { to: "/operator/tracking", label: "Tracking Mezzi", icon: Activity },
  { to: "/operator/maintenance", label: "Manutenzione", icon: Wrench },
  { to: "/operator/bonuses", label: "Bonus Parcheggio", icon: Gift },
  { to: "/operator/end-location", label: "Posizione Fine Corsa", icon: MapPin },
  { to: "/operator/users", label: "Gestione Utenti", icon: Users },
]

export function OperatorLayout() {
  const { profile, signOut } = useAuth()
  const navigate = useNavigate()

  return (
    <div className="operator-layout">
      <aside className="bg-[var(--surface-lowest)] flex flex-col">
        <div className="px-6 pt-7 pb-6">
          <Link to="/operator" className="flex items-center gap-3">
            <div className="size-10 rounded-2xl btn-primary-grad flex items-center justify-center font-display text-xl font-extrabold">
              Z
            </div>
            <div>
              <p className="label-sm text-[var(--muted-foreground)]">ZooSmart</p>
              <p className="font-bold text-base leading-tight">Operator</p>
            </div>
          </Link>
        </div>

        <nav className="flex-1 px-3 flex flex-col gap-1">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                cn(
                  "flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-semibold transition-colors",
                  isActive
                    ? "bg-[var(--surface-low)] text-[var(--primary)] ghost-active"
                    : "text-[var(--muted-foreground)] hover:bg-[var(--surface-low)] hover:text-[var(--foreground)]"
                )
              }
            >
              <item.icon className="size-5" />
              {item.label}
            </NavLink>
          ))}
        </nav>

        <div className="p-4 mx-3 mb-4 rounded-2xl bg-[var(--surface-low)]">
          <p className="label-sm text-[var(--muted-foreground)]">CONNESSO COME</p>
          <p className="font-bold text-sm mt-0.5 truncate">{profile?.display_name}</p>
          <p className="text-xs text-[var(--muted-foreground)] truncate">{profile?.email}</p>
          <Button
            variant="ghost"
            size="sm"
            onClick={async () => {
              await signOut()
              navigate("/login")
            }}
            className="mt-3 w-full justify-start rounded-xl text-[var(--muted-foreground)] hover:text-[var(--destructive)]"
          >
            <LogOut className="size-4" /> Esci
          </Button>
        </div>
      </aside>

      <main className="overflow-x-hidden">
        <Outlet />
      </main>
    </div>
  )
}
