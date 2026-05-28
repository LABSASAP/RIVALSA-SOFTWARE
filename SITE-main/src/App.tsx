import { Navigate, Route, Routes } from "react-router-dom"
import { useAuth } from "@/lib/auth-context"
import { LoginPage } from "@/pages/login"
import { NearbyPage } from "@/pages/nearby"
import { VehicleDetailPage } from "@/pages/vehicle-detail"
import { ReservationPage } from "@/pages/reservation"
import { RidePage } from "@/pages/ride"
import { RideSummaryPage } from "@/pages/ride-summary"
import { PaymentMethodsPage } from "@/pages/payment-methods"
import { ProfilePage } from "@/pages/profile"
import { ReportVehiclePage } from "@/pages/report-vehicle"
import { CreditsPage } from "@/pages/credits"
import { SupportPage } from "@/pages/support"
import { OperatorLayout } from "@/pages/operator/layout"
import { OperatorReportsPage } from "@/pages/operator/reports"
import { OperatorReservationsPage } from "@/pages/operator/reservations"
import { OperatorEndLocationPage } from "@/pages/operator/end-location"
import { OperatorUsersPage } from "@/pages/operator/users"
import { OperatorSupportPage } from "@/pages/operator/support"
import { OperatorFleetPage } from "@/pages/operator/fleet"
import { OperatorTrackingPage } from "@/pages/operator/tracking"
import { OperatorMaintenancePage } from "@/pages/operator/maintenance"
import { OperatorBonusesPage } from "@/pages/operator/bonuses"
import { PublicAdminLayout } from "@/pages/public-admin/layout"
import { PublicAdminDashboardPage } from "@/pages/public-admin/dashboard"
import { PublicAdminZonesPage } from "@/pages/public-admin/zones"
import { PublicAdminRoutesPage } from "@/pages/public-admin/routes"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import type { Role } from "@/lib/supabase"

function Splash() {
  return (
    <div className="app-shell flex flex-col items-center justify-center min-h-svh gap-4">
      <div className="size-20 rounded-3xl btn-primary-grad flex items-center justify-center font-display text-4xl font-extrabold shadow-[0_16px_40px_rgba(0,64,161,0.25)]">
        Z
      </div>
      <div className="text-center">
        <p className="label-sm text-[var(--muted-foreground)]">URBAN MOBILITY</p>
        <h1 className="text-3xl font-extrabold tracking-tight mt-0.5">ZooSmart</h1>
      </div>
      <Spinner />
    </div>
  )
}

function SetupRequired() {
  const { signOut } = useAuth()

  return (
    <div className="app-shell flex flex-col items-center justify-center min-h-svh px-6">
      <div className="max-w-sm w-full rounded-3xl bg-[var(--surface-lowest)] p-6 shadow-[0_12px_32px_rgba(25,28,29,0.04)]">
        <p className="label-sm text-[var(--muted-foreground)]">SUPABASE SETUP</p>
        <h1 className="text-2xl font-extrabold tracking-tight mt-1">Profilo utente mancante</h1>
        <p className="text-sm text-[var(--muted-foreground)] mt-3 leading-relaxed">
          L&apos;accesso Auth esiste, ma nel database manca la riga corrispondente in <span className="font-mono">profiles</span>.
        </p>
        <div className="mt-4 rounded-2xl bg-[var(--surface-low)] p-4 text-sm text-[var(--muted-foreground)] leading-relaxed">
          Esegui la migration <span className="font-mono">20260515170000_zoosmart_local_bootstrap.sql</span>, poi esci e rientra.
        </div>
        <Button
          onClick={async () => {
            await signOut()
          }}
          className="mt-5 h-12 w-full rounded-2xl btn-primary-grad font-bold"
        >
          Esci e riprova
        </Button>
      </div>
    </div>
  )
}

function roleHome(role: Role | undefined) {
  if (role === "operator") return "/operator"
  if (role === "public_admin") return "/public-admin"
  return "/nearby"
}

function Protected({ children, role }: { children: React.ReactNode; role?: Role }) {
  const { session, profile, loading } = useAuth()
  if (loading) return <Splash />
  if (!session) return <Navigate to="/login" replace />
  if (!profile) return <SetupRequired />
  if (role && profile?.role !== role) {
    return <Navigate to={roleHome(profile?.role)} replace />
  }
  return <>{children}</>
}

function RootRedirect() {
  const { session, profile, loading } = useAuth()
  if (loading) return <Splash />
  if (!session) return <Navigate to="/login" replace />
  if (!profile) return <SetupRequired />
  return <Navigate to={roleHome(profile.role)} replace />
}

export function App() {
  return (
    <Routes>
      <Route path="/" element={<RootRedirect />} />
      <Route path="/login" element={<LoginPage />} />

      <Route path="/nearby" element={<Protected role="user"><NearbyPage /></Protected>} />
      <Route path="/vehicles/:id" element={<Protected role="user"><VehicleDetailPage /></Protected>} />
      <Route path="/reservation" element={<Protected role="user"><ReservationPage /></Protected>} />
      <Route path="/ride" element={<Protected role="user"><RidePage /></Protected>} />
      <Route path="/ride/:id/summary" element={<Protected role="user"><RideSummaryPage /></Protected>} />
      <Route path="/payment-methods" element={<Protected role="user"><PaymentMethodsPage /></Protected>} />
      <Route path="/profile" element={<Protected role="user"><ProfilePage /></Protected>} />
      <Route path="/report" element={<Protected role="user"><ReportVehiclePage /></Protected>} />
      <Route path="/credits" element={<Protected role="user"><CreditsPage /></Protected>} />
      <Route path="/support" element={<Protected role="user"><SupportPage /></Protected>} />

      <Route path="/operator" element={<Protected role="operator"><OperatorLayout /></Protected>}>
        <Route index element={<OperatorReportsPage />} />
        <Route path="reservations" element={<OperatorReservationsPage />} />
        <Route path="end-location" element={<OperatorEndLocationPage />} />
        <Route path="users" element={<OperatorUsersPage />} />
        <Route path="support" element={<OperatorSupportPage />} />
        <Route path="fleet" element={<OperatorFleetPage />} />
        <Route path="tracking" element={<OperatorTrackingPage />} />
        <Route path="maintenance" element={<OperatorMaintenancePage />} />
        <Route path="bonuses" element={<OperatorBonusesPage />} />
      </Route>

      <Route path="/public-admin" element={<Protected role="public_admin"><PublicAdminLayout /></Protected>}>
        <Route index element={<PublicAdminDashboardPage />} />
        <Route path="zones" element={<PublicAdminZonesPage />} />
        <Route path="routes" element={<PublicAdminRoutesPage />} />
      </Route>

      <Route path="*" element={<RootRedirect />} />
    </Routes>
  )
}

export default App
