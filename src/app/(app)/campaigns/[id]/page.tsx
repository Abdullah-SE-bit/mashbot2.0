import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Campaign, CampaignContent, Profile } from "@/lib/types";
import { AddContentForm } from "@/components/campaigns/add-content-form";
import { ContentItem } from "@/components/campaigns/content-item";
import { ActionButton } from "@/components/ui/action-button";
import { deleteCampaign } from "@/lib/actions/campaigns";

export default async function CampaignDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) notFound();

  const [{ data: campaign }, { data: profile }, { data: content }] = await Promise.all([
    supabase.from("campaigns").select("*").eq("id", id).single<Campaign>(),
    supabase.from("profiles").select("*").eq("id", user.id).single<Profile>(),
    supabase
      .from("campaign_content")
      .select("*")
      .eq("campaign_id", id)
      .order("created_at", { ascending: false })
      .returns<CampaignContent[]>(),
  ]);

  if (!campaign || !profile) notFound();

  const canManageCampaign = campaign.owner_id === profile.id || profile.account_type === "admin";

  return (
    <div className="flex flex-col gap-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold">{campaign.name}</h1>
          <p className="text-sm text-zinc-600">
            {campaign.start_date ?? "no start date"} – {campaign.end_date ?? "no end date"}
          </p>
        </div>
        {canManageCampaign && (
          <div className="flex gap-2">
            <Link
              href={`/campaigns/${campaign.id}/edit`}
              className="rounded-md border border-zinc-300 px-3 py-1.5 text-sm hover:bg-zinc-100"
            >
              Edit
            </Link>
            <ActionButton
              variant="danger"
              confirmMessage="Delete this campaign and all of its content?"
              action={deleteCampaign.bind(null, campaign.id)}
            >
              Delete campaign
            </ActionButton>
          </div>
        )}
      </div>

      {profile.roles.includes("contributor") && <AddContentForm campaignId={campaign.id} />}

      <div>
        <h2 className="mb-3 text-lg font-medium">Content</h2>
        {(content?.length ?? 0) === 0 ? (
          <p className="text-sm text-zinc-600">No content yet.</p>
        ) : (
          <ul className="flex flex-col gap-3">
            {content?.map((item) => (
              <ContentItem
                key={item.id}
                content={item}
                campaignId={campaign.id}
                profile={profile}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
