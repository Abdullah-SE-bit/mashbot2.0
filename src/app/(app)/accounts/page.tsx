import { createClient } from "@/lib/supabase/server";
import type { ExternalServiceAccount } from "@/lib/types";
import { ConnectAccountForm } from "@/components/accounts/connect-account-form";
import { ActionButton } from "@/components/ui/action-button";
import { disconnectExternalAccount } from "@/lib/actions/externalAccounts";

export default async function AccountsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: accounts } = await supabase
    .from("external_service_accounts")
    .select("*")
    .eq("user_id", user?.id ?? "")
    .order("created_at", { ascending: false })
    .returns<ExternalServiceAccount[]>();

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold">External service accounts</h1>
        <p className="text-sm text-zinc-600">
          SRS 0590–0610. Connections here are simulated for this MVP — see docs/assumptions.md.
        </p>
      </div>

      <ConnectAccountForm />

      <ul className="flex flex-col gap-3">
        {accounts?.map((account) => (
          <li
            key={account.id}
            className="flex items-center justify-between rounded-lg border border-zinc-200 bg-white p-4"
          >
            <div>
              <p className="font-medium capitalize">{account.provider}</p>
              <p className="text-sm text-zinc-600">@{account.external_username}</p>
            </div>
            <div className="flex items-center gap-3">
              <span
                className={`text-xs font-medium ${account.status === "connected" ? "text-emerald-700" : "text-zinc-500"}`}
              >
                {account.status}
              </span>
              {account.status === "connected" && (
                <ActionButton action={disconnectExternalAccount.bind(null, account.id)}>
                  Disconnect
                </ActionButton>
              )}
            </div>
          </li>
        ))}
        {(accounts?.length ?? 0) === 0 && (
          <p className="text-sm text-zinc-600">No external accounts connected yet.</p>
        )}
      </ul>
    </div>
  );
}
