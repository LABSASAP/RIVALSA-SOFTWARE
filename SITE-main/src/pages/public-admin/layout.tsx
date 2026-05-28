import { Link, NavLink, Outlet, useNavigate } from "react-router-dom"
import { BarChart3, LogOut, MapPinned, Route } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuth } from "@/lib/auth-context"
import { cn } from "@/lib/utils"

const NAV = [
  { to: "/public-admin", label: "Report Mobilita", icon: BarChart3, end: true },
  { to: "/public-admin/zones", label: "Zone Urbane", icon: MapPinned },
  { to: "/public-admin/routes", label: "Tratte Utilizzate", icon: Route },
]

export function PublicAdminLayout() {
  const { profile, signOut } = useAuth()
  const navigate = useNavigate()

  return (
    <div className="operator-layout">
      <aside className="flex flex-col bg-[var(--surface-lowest)]">
        <div className="px-6 pb-6 pt-7">
          <Link to="/public-admin" className="flex items-center gap-3">
            <div className="flex size-10 items-center justify-center rounded-2xl btn-primary-grad font-display text-xl font-extrabold">
              Z
            </div>
            <div>
              <p className="label-sm text-[var(--muted-foreground)]">ZooSmart</p>
              <p className="text-base font-bold leading-tight">Comune</p>
            </div>
          </Link>
        </div>

        <nav className="flex flex-1 flex-col gap-1 px-3">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                cn(
                  "flex items-center gap-3 rounded-2xl px-4 py-3 text-sm font-semibold transition-colors",
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

        <div className="mx-3 mb-4 rounded-2xl bg-[var(--surface-low)] p-4">
          <p className="label-sm text-[var(--muted-foreground)]">CONNESSO COME</p>
          <p className="mt-0.5 truncate text-sm font-bold">{profile?.display_name}</p>
          <p className="truncate text-xs text-[var(--muted-foreground)]">{profile?.email}</p>
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

export function PublicAdminHeader({ title, subtitle, action }: { title: string; subtitle?: string; action?: React.ReactNode }) {
  return (
    <div className="glass-header flex flex-col items-start justify-between gap-4 px-5 pb-5 pt-7 lg:flex-row lg:items-end lg:px-10 lg:pt-9">
      <div>
        <p className="label-sm text-[var(--muted-foreground)]">DASHBOARD COMUNALE</p>
        <h1 className="mt-1 text-3xl font-extrabold tracking-tight">{title}</h1>
        {subtitle && <p className="mt-1 text-[var(--muted-foreground)]">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

export function PublicAdminBody({ children, className }: { children: React.ReactNode; className?: string }) {
  return <div className={cn("px-5 pb-12 pt-2 lg:px-10", className)}>{children}</div>
}
