import {
  Box,
  Button,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type FactionJob = {
  title: string;
  rank: number;
  pay_rate: number;
  access_descs: string[];
};

type KnownFaction = {
  uid: string;
  name: string;
};

type FactionTransaction = {
  amount: number;
  reason: string;
  when: string;
};

type FactionMember = {
  ckey: string;
  real_name: string;
  job_title: string | null;
  rank: number;
};

type FactionIdPurge = {
  issued_by: string;
  revoked_count: number;
  member_count: number;
  when: string;
};

type FoundingPetition = {
  target_uid: string;
  founder_name: string;
  faction_name: string;
  abbreviation: string;
  supporter_count: number;
  is_founder: BooleanLike;
  already_supported: BooleanLike;
};

type FactionData = {
  faction_uid: string | null;
  faction_name: string | null;
  faction_registered: BooleanLike;
  op_rank: number; // -2 = not linked, -1 = non-member, 0+ = rank, 99 = admin
  balance: number | null;
  last_payroll: number;
  auto_payroll: BooleanLike;
  jobs: FactionJob[];
  known_factions: KnownFaction[];
  transactions: FactionTransaction[];
  members: FactionMember[];
  cards_epoch: number;
  id_purges: FactionIdPurge[];
  is_founder: BooleanLike;
  master_card_lost: BooleanLike;
  color: string | null;
  faction_creation_enabled: BooleanLike;
  founding_required: number;
  petitions: FoundingPetition[];
};

// Global program feature -- available from ANY console regardless of that
// console's own shackle/registration state. Rendered in every branch below.
const FoundingSection = (props: {
  faction_creation_enabled: BooleanLike;
  founding_required: number;
  petitions: FoundingPetition[];
}) => {
  const { act } = useBackend<FactionData>();
  const { faction_creation_enabled, founding_required, petitions } = props;
  return (
    <Section title="Found a New Faction">
      {!faction_creation_enabled && (
        <NoticeBox danger>
          Faction founding is currently disabled by administrators.
        </NoticeBox>
      )}
      <Box mt={1}>
        <Button
          icon="plus"
          color="good"
          disabled={!faction_creation_enabled}
          tooltip="Starts a founding petition for 100,000 credits from your own bank account (charged only once other players consent). You become its first command-rank member."
          onClick={() => act('start_founding')}
        >
          Start Founding Petition (100,000 cr)
        </Button>
      </Box>
      {petitions.length > 0 && (
        <Table mt={1}>
          <Table.Row header>
            <Table.Cell>Faction</Table.Cell>
            <Table.Cell>Founder</Table.Cell>
            <Table.Cell>Support</Table.Cell>
            <Table.Cell />
          </Table.Row>
          {petitions.map((p) => (
            <Table.Row key={p.target_uid}>
              <Table.Cell bold>
                {p.faction_name} ({p.abbreviation})
              </Table.Cell>
              <Table.Cell color="label">{p.founder_name}</Table.Cell>
              <Table.Cell>
                {p.supporter_count}/{founding_required}
              </Table.Cell>
              <Table.Cell>
                {p.is_founder ? (
                  <Box italic color="label">
                    You started this
                  </Box>
                ) : p.already_supported ? (
                  <Box color="good">Supported</Box>
                ) : (
                  <>
                    <Button
                      compact
                      icon="thumbs-up"
                      color="good"
                      onClick={() =>
                        act('support_founding', { target_uid: p.target_uid })
                      }
                    >
                      Support
                    </Button>
                    <Button
                      compact
                      icon="hand-pointer"
                      onClick={() =>
                        act('select_tap_target', {
                          target_uid: p.target_uid,
                        })
                      }
                    >
                      Canvas via tap
                    </Button>
                  </>
                )}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};

const RANK_LABELS = ['Crew', 'Officer', 'Command'];

export const FactionManagement = (props) => {
  const { act, data } = useBackend<FactionData>();
  const [transferTarget, setTransferTarget] = useState('');
  const [transferAmount, setTransferAmount] = useState(0);

  const {
    faction_uid,
    faction_name,
    faction_registered,
    op_rank,
    balance,
    last_payroll,
    auto_payroll,
    jobs,
    known_factions,
    members,
    cards_epoch,
    is_founder,
    master_card_lost,
    color,
    faction_creation_enabled,
    founding_required,
    petitions,
  } = data;
  const [colorPick, setColorPick] = useState(color ?? '#ffffff');

  const foundingSection = (
    <FoundingSection
      faction_creation_enabled={faction_creation_enabled}
      founding_required={founding_required}
      petitions={petitions ?? []}
    />
  );

  if (!faction_uid) {
    return (
      <NtosWindow width={500} height={480}>
        <NtosWindow.Content scrollable>
          <NoticeBox>
            This console is not linked to a faction. Use a faction tagger
            tool on the computer to shackle it to a network, or found a new
            faction below regardless of this console's own state.
          </NoticeBox>
          {foundingSection}
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  // Faction UID set but not yet registered in DB.
  if (!faction_registered) {
    return (
      <NtosWindow width={500} height={480}>
        <NtosWindow.Content scrollable>
          <NoticeBox>
            The network &quot;{faction_uid}&quot; has not been registered as
            a faction yet.
          </NoticeBox>
          {foundingSection}
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  if (op_rank < 1) {
    return (
      <NtosWindow width={500} height={480}>
        <NtosWindow.Content scrollable>
          <Section title={faction_name ?? faction_uid}>
            <NoticeBox>
              You are not a member of {faction_name ?? faction_uid} or do not
              have officer access.
            </NoticeBox>
          </Section>
          {foundingSection}
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  const canManage = op_rank >= 2;

  return (
    <NtosWindow resizable width={650} height={700}>
      <NtosWindow.Content scrollable>
        {/* Account Section */}
        <Section title={`${faction_name ?? faction_uid} — Account`}>
          <LabeledList>
            <LabeledList.Item label="Balance">
              {`${balance ?? 0} credits`}
            </LabeledList.Item>
            <LabeledList.Item label="Last Payroll">
              {last_payroll > 0
                ? `${Math.floor(last_payroll / 600)} min ago`
                : 'Not yet this session'}
            </LabeledList.Item>
            <LabeledList.Item label="Payroll Mode">
              {auto_payroll ? 'Automatic (every autosave)' : 'Manual only'}
              {canManage && (
                <Button
                  ml={1}
                  icon="toggle-on"
                  onClick={() => act('toggle_auto_payroll')}
                >
                  Switch to {auto_payroll ? 'Manual' : 'Automatic'}
                </Button>
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Faction Color">
              <Box
                inline
                mr={1}
                style={{
                  display: 'inline-block',
                  width: '16px',
                  height: '16px',
                  verticalAlign: 'middle',
                  backgroundColor: color ?? '#ffffff',
                  border: '1px solid #666666',
                }}
              />
              {color ?? 'Not set'}
              {canManage && (
                <>
                  <input
                    type="color"
                    value={colorPick}
                    onChange={(e) => setColorPick(e.target.value)}
                    style={{ marginLeft: '8px', verticalAlign: 'middle' }}
                  />
                  <Button
                    ml={1}
                    icon="paint-roller"
                    tooltip="Tints any clothing/equipment currently tagged to this faction with the faction tagger, immediately."
                    onClick={() => act('set_faction_color', { color: colorPick })}
                  >
                    Set
                  </Button>
                </>
              )}
            </LabeledList.Item>
          </LabeledList>
          {canManage && (
            <Box mt={1}>
              <Button
                icon="coins"
                color="good"
                onClick={() => act('pay_now')}
              >
                Pay Members Now
              </Button>
              <Button
                icon="user"
                color="caution"
                ml={1}
                onClick={() => act('transfer_player')}
              >
                Pay Player...
              </Button>
              <Button
                icon="credit-card"
                color="average"
                ml={1}
                tooltip="Print a charge card that draws directly on the faction account. Anyone holding it can spend faction funds."
                onClick={() => act('print_charge_card')}
              >
                Print Charge Card
              </Button>
              <Button
                icon="ban"
                color="bad"
                ml={1}
                tooltip={`Voids every charge card ever printed for this faction (currently on epoch ${cards_epoch}). Cards printed after this will still work.`}
                onClick={() => act('invalidate_charge_cards')}
              >
                Invalidate All Charge Cards
              </Button>
              {(!!is_founder || op_rank === 99) && !!master_card_lost && (
                <Button
                  icon="id-card"
                  color="good"
                  ml={1}
                  tooltip="Prints a replacement faction master card. Only available to the original founder (or an admin), and only while the current one is reported lost (Panic Purge)."
                  onClick={() => act('print_master_card')}
                >
                  Print Master Card
                </Button>
              )}
            </Box>
          )}
          {canManage && known_factions.length > 0 && (
            <Box mt={1}>
              <Box bold mb={1}>
                Transfer Credits
              </Box>
              <Stack>
                <Stack.Item>
                  <select
                    value={transferTarget}
                    onChange={(e) => setTransferTarget(e.target.value)}
                    style={{ marginRight: '4px' }}
                  >
                    <option value="">-- Select faction --</option>
                    {known_factions.map((f) => (
                      <option key={f.uid} value={f.uid}>
                        {f.name}
                      </option>
                    ))}
                  </select>
                </Stack.Item>
                <Stack.Item>
                  <NumberInput
                    value={transferAmount}
                    minValue={1}
                    maxValue={balance ?? 0}
                    onChange={(val) => setTransferAmount(val)}
                    width="80px"
                  />
                </Stack.Item>
                <Stack.Item>
                  <Button
                    color="good"
                    disabled={!transferTarget || transferAmount <= 0}
                    onClick={() =>
                      act('transfer_credits', {
                        target_uid: transferTarget,
                        amount: transferAmount,
                      })
                    }
                  >
                    Transfer
                  </Button>
                </Stack.Item>
              </Stack>
            </Box>
          )}
        </Section>

        {/* Jobs Section */}
        <Section
          title="Faction Jobs"
          buttons={
            canManage && (
              <Button icon="plus" onClick={() => act('add_job')}>
                Add Job
              </Button>
            )
          }
        >
          {jobs.length === 0 ? (
            <Box italic color="label">
              No jobs defined. {canManage && 'Click "Add Job" to create one.'}
            </Box>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Title</Table.Cell>
                <Table.Cell>Rank</Table.Cell>
                <Table.Cell>Pay/cycle</Table.Cell>
                <Table.Cell>Access</Table.Cell>
                {canManage && <Table.Cell />}
              </Table.Row>
              {jobs.map((job) => (
                <Table.Row key={job.title}>
                  <Table.Cell bold>{job.title}</Table.Cell>
                  <Table.Cell>
                    {RANK_LABELS[job.rank] ?? `Rank ${job.rank}`}
                  </Table.Cell>
                  <Table.Cell>{job.pay_rate} cr</Table.Cell>
                  <Table.Cell color="label">
                    {job.access_descs.length === 0
                      ? 'None'
                      : job.access_descs.length <= 3
                        ? job.access_descs.join(', ')
                        : `${job.access_descs.slice(0, 3).join(', ')} … +${job.access_descs.length - 3} more`}
                  </Table.Cell>
                  {canManage && (
                    <Table.Cell>
                      <Button
                        compact
                        onClick={() =>
                          act('edit_job', { job_title: job.title })
                        }
                      >
                        Edit
                      </Button>
                      <Button
                        compact
                        color="bad"
                        onClick={() =>
                          act('remove_job', { job_title: job.title })
                        }
                      >
                        Remove
                      </Button>
                    </Table.Cell>
                  )}
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>

        {/* Members Section */}
        <Section
          title="Faction Members"
          buttons={
            canManage && (
              <Button
                color="bad"
                icon="skull-crossbones"
                tooltip="Revokes EVERY ID card this faction has ever issued, live or offline, except your own. Cannot be undone."
                onClick={() => act('panic_purge_ids')}
              >
                Panic Purge IDs
              </Button>
            )
          }
        >
          {!members || members.length === 0 ? (
            <Box italic color="label">
              No registered members found.
            </Box>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Name</Table.Cell>
                <Table.Cell>Job</Table.Cell>
                <Table.Cell>Rank</Table.Cell>
                {canManage && <Table.Cell />}
              </Table.Row>
              {members.map((member) => (
                <Table.Row key={member.ckey}>
                  <Table.Cell bold>{member.real_name}</Table.Cell>
                  <Table.Cell color="label">
                    {member.job_title ?? 'Unassigned'}
                  </Table.Cell>
                  <Table.Cell>
                    {RANK_LABELS[member.rank] ?? `Rank ${member.rank}`}
                  </Table.Cell>
                  {canManage && (
                    <Table.Cell>
                      <Button
                        compact
                        color="bad"
                        icon="id-card"
                        tooltip="Revokes this member's faction ID immediately if they're in the world, and automatically the next time they (or their ID) show up otherwise."
                        onClick={() =>
                          act('revoke_member_id', {
                            target_ckey: member.ckey,
                          })
                        }
                      >
                        Revoke ID
                      </Button>
                    </Table.Cell>
                  )}
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>

        {/* Transaction History */}
        {data.transactions?.length > 0 && (
          <Section title="Transaction History">
            <Table>
              <Table.Row header>
                <Table.Cell>Amount</Table.Cell>
                <Table.Cell>Description</Table.Cell>
                <Table.Cell>Time</Table.Cell>
              </Table.Row>
              {(data.transactions ?? []).map((tx, i) => (
                <Table.Row key={i}>
                  <Table.Cell
                    bold
                    color={tx.amount >= 0 ? 'good' : 'bad'}
                  >
                    {tx.amount >= 0 ? '+' : ''}
                    {tx.amount} cr
                  </Table.Cell>
                  <Table.Cell>{tx.reason}</Table.Cell>
                  <Table.Cell color="label">{tx.when}</Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Section>
        )}

        {/* Panic Purge Audit Trail */}
        {data.id_purges?.length > 0 && (
          <Section title="ID Purge History">
            <Table>
              <Table.Row header>
                <Table.Cell>Issued By</Table.Cell>
                <Table.Cell>Revoked</Table.Cell>
                <Table.Cell>Members</Table.Cell>
                <Table.Cell>Time</Table.Cell>
              </Table.Row>
              {(data.id_purges ?? []).map((purge, i) => (
                <Table.Row key={i}>
                  <Table.Cell bold>{purge.issued_by}</Table.Cell>
                  <Table.Cell color="bad">{purge.revoked_count}</Table.Cell>
                  <Table.Cell color="label">{purge.member_count}</Table.Cell>
                  <Table.Cell color="label">{purge.when}</Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Section>
        )}

        {foundingSection}
      </NtosWindow.Content>
    </NtosWindow>
  );
};
