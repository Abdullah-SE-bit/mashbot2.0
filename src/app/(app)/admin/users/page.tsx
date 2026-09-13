import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile } from "@/lib/types";
import { ActionButton } from "@/components/ui/action-button";
import { RolesEditor } from "@/components/admin/roles-editor";
import { deactivateUser, deleteUser, reactivateUser } from "@/lib/actions/users";

export default async function AdminUsersPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: me } = await supabase
    .from("profiles")
    .select("account_type")
    .eq("id", user.id)
    .single();

  if (me?.account_type !== "admin") {
    redirect("/dashboard");
  }

  const { data: users } = await supabase
    .from("profiles")
    .select("*")
    .order("created_at", { ascending: true })
    .returns<Profile[]>();

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold">Manage user accounts</h1>
        <p className="text-sm text-zinc-600">
          SRS 0380–0430 — deactivate, reactivate, or delete accounts with no history.
        </p>
      </div>

      <div className="overflow-x-auto rounded-lg border border-zinc-200 bg-white">
        <table className="min-w-full divide-y divide-zinc-200 text-sm">
          <thead>
            <tr className="text-left text-zinc-500">
              <th className="px-4 py-2">Name</th>
              <th className="px-4 py-2">Email</th>
              <th className="px-4 py-2">Roles</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-100">
            {users?.map((profile) => (
              <tr key={profile.id}>
                <td className="px-4 py-2 font-medium">{profile.name}</td>
                <td className="px-4 py-2">{profile.email}</td>
                <td className="px-4 py-2">
                  {profile.account_type === "admin" ? (
                    "—"
                  ) : (
                    <RolesEditor userId={profile.id} roles={profile.roles} />
                  )}
                </td>
                <td className="px-4 py-2">
                  <span
                    className={
                      profile.status === "active" ? "text-emerald-700" : "text-zinc-500"
                    }
                  >
                    {profile.status}
                  </span>
                  {profile.account_type === "admin" && (
                    <span className="ml-2 text-xs text-zinc-400">(admin)</span>
                  )}
                </td>
                <td className="px-4 py-2">
                  {profile.account_type !== "admin" && (
                    <div className="flex gap-2">
                      {profile.status === "active" ? (
                        <ActionButton action={deactivateUser.bind(null, profile.id)}>
                          Deactivate
                        </ActionButton>
                      ) : (
                        <ActionButton action={reactivateUser.bind(null, profile.id)}>
                          Reactivate
                        </ActionButton>
                      )}
                      <ActionButton
                        variant="danger"
                        confirmMessage="Delete this account? Only possible if it has no history."
                        action={deleteUser.bind(null, profile.id)}
                      >
                        Delete
                      </ActionButton>
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
