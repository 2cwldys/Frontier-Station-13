import {
  Box,
  Button,
  Dropdown,
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
  clocked_in: BooleanLike;
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
  is_company: BooleanLike;
  required_supporters: number;
};

type Shareholder = {
  char_name: string;
  percent: number;
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
  can_print_master_card: BooleanLike;
  can_disband_faction: BooleanLike;
  color: string | null;
  allowed_cargo_category?: string | null;
  cargo_category_options?: string[];
  cargo_category_cooldown_remaining?: number;
  allies?: KnownFaction[];
  incoming_alliance_requests?: KnownFaction[];
  outgoing_alliance_requests?: KnownFaction[];
  alliance_targets?: KnownFaction[];
  faction_creation_enabled: BooleanLike;
  founding_required: number;
  founding_required_company: number;
  founding_cost: number;
  founding_cost_company: number;
  petitions: FoundingPetition[];
  stock_listed: BooleanLike;
  stock_ticker: string | null;
  stock_player_shares: number;
  is_ceo: BooleanLike;
  shareholders: Shareholder[];
  shareholder_total_percent: number;
};

// Global program feature -- available from ANY console regardless of that
// console's own shackle/registration state. Rendered in every branch below.
const FoundingSection = (props: {
  faction_creation_enabled: BooleanLike;
  founding_required: number;
  founding_required_company: number;
  founding_cost: number;
  founding_cost_company: number;
  petitions: FoundingPetition[];
}) => {
  const { act } = useBackend<FactionData>();
  const {
    faction_creation_enabled,
    founding_required,
    founding_required_company,
    founding_cost,
    founding_cost_company,
    petitions,
  } = props;
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
          tooltip={`Starts a founding petition for ${founding_cost_company.toLocaleString()} credits (needs ${founding_required_company} supporters). You become its first command-rank member, and it's automatically listed on the stock exchange in your name. Stays limited to one cargo order category.`}
          onClick={() => act('start_founding', { tier: 'company' })}
        >
          Start Company ({founding_cost_company.toLocaleString()} cr)
        </Button>
        <Button
          icon="plus"
          color="good"
          ml={1}
          disabled={!faction_creation_enabled}
          tooltip={`Starts a founding petition for ${founding_cost.toLocaleString()} credits (needs ${founding_required} supporters) from your own bank account, charged only once other players consent. You become its first command-rank member, and it gets unrestricted cargo ordering across every category.`}
          onClick={() => act('start_founding', { tier: 'full' })}
        >
          Start Full Faction ({founding_cost.toLocaleString()} cr)
        </Button>
      </Box>
      {petitions.length > 0 && (
        <Table mt={1}>
          <Table.Row header>
            <Table.Cell>Faction</Table.Cell>
            <Table.Cell>Tier</Table.Cell>
            <Table.Cell>Founder</Table.Cell>
            <Table.Cell>Support</Table.Cell>
            <Table.Cell />
          </Table.Row>
          {petitions.map((p) => (
            <Table.Row key={p.target_uid}>
              <Table.Cell bold>
                {p.faction_name} ({p.abbreviation})
              </Table.Cell>
              <Table.Cell color={p.is_company ? 'label' : 'good'}>
                {p.is_company ? 'Company' : 'Full Faction'}
              </Table.Cell>
              <Table.Cell color="label">{p.founder_name}</Table.Cell>
              <Table.Cell>
                {p.supporter_count}/{p.required_supporters}
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
  const [allianceTarget, setAllianceTarget] = useState('');

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
    can_print_master_card,
    can_disband_faction,
    color,
    allowed_cargo_category,
    cargo_category_options,
    cargo_category_cooldown_remaining,
    allies,
    incoming_alliance_requests,
    outgoing_alliance_requests,
    alliance_targets,
    faction_creation_enabled,
    founding_required,
    founding_required_company,
    founding_cost,
    founding_cost_company,
    petitions,
    stock_listed,
    stock_ticker,
    stock_player_shares,
    is_ceo,
    shareholders,
    shareholder_total_percent,
  } = data;
  const [colorPick, setColorPick] = useState(color ?? '#ffffff');

  const foundingSection = (
    <FoundingSection
      faction_creation_enabled={faction_creation_enabled}
      founding_required={founding_required}
      founding_required_company={founding_required_company}
      founding_cost={founding_cost}
      founding_cost_company={founding_cost_company}
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
        <Section
          title={
            <>
              {faction_name ?? faction_uid} — Account
              {!!is_ceo && (
                <Box as="span" ml={1} color="good" bold>
                  (CEO)
                </Box>
              )}
            </>
          }
        >
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
            {cargo_category_options && cargo_category_options.length > 0 && (
              <LabeledList.Item label="Cargo Specialization">
                {allowed_cargo_category || 'None chosen -- cannot order from cargo yet'}
                {canManage && (
                  <Dropdown
                    ml={1}
                    width="160px"
                    options={cargo_category_options}
                    displayText="Change..."
                    onSelected={(value) =>
                      act('set_cargo_category', { category: value })
                    }
                  />
                )}
                {!!cargo_category_cooldown_remaining && cargo_category_cooldown_remaining > 0 && (
                  <Box mt={1} color="bad">
                    Locked for {Math.ceil(cargo_category_cooldown_remaining / 86400)}{' '}
                    more day(s).
                  </Box>
                )}
              </LabeledList.Item>
            )}
            <LabeledList.Item label="Stock Exchange">
              {stock_listed ? (
                <>
                  Listed as <Box as="span" bold>{stock_ticker}</Box> --{' '}
                  {stock_player_shares} share(s) held by investors
                </>
              ) : (
                'Not listed'
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
              {stock_listed ? (
                <>
                  <Button
                    icon="hand-holding-usd"
                    color="good"
                    ml={1}
                    tooltip="Distributes credits from the faction treasury to every current shareholder, split by their exact percent of the company. Always leaves at least 1% of the treasury behind."
                    onClick={() => act('pay_dividends')}
                  >
                    Pay Dividends
                  </Button>
                  <Button
                    icon="file-contract"
                    color="average"
                    ml={1}
                    tooltip="Prints a share certificate offering a set percentage of the company (optionally for a price) -- swiping an ID against it accepts the stake, diluting every current shareholder proportionally."
                    onClick={() => act('print_share_certificate')}
                  >
                    Print Share Certificate
                  </Button>
                </>
              ) : (
                <Button
                  icon="chart-line"
                  color="average"
                  ml={1}
                  tooltip="Lists this faction on the Idris stock exchange -- real players can then buy/sell stock tied directly to the faction treasury, and you become the company's first shareholder at 100%. If the treasury runs dry, every stockholder is force-liquidated and the faction is dissolved entirely. Cannot be undone by faction command; only an admin can revoke it afterward."
                  onClick={() => act('list_on_exchange')}
                >
                  List on Stock Exchange
                </Button>
              )}
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
              {!!can_print_master_card && (
                <Button
                  icon="id-card"
                  color="good"
                  ml={1}
                  tooltip="Prints a replacement faction master card. Only available to the original founder, the majority shareholder, the designated leader, or an admin, and only while the current one is reported lost (Panic Purge) or none has ever been printed."
                  onClick={() => act('print_master_card')}
                >
                  Print Master Card
                </Button>
              )}
              {!!can_disband_faction && (
                <Button
                  icon="trash"
                  color="bad"
                  ml={1}
                  tooltip="Permanently disbands this faction -- treasury, jobs, beacon claims, drydock ship ownership, and stock listing all gone. Only available to the original founder, the majority shareholder, the designated leader, or an admin. Cannot be undone."
                  onClick={() => act('disband_faction')}
                >
                  Disband Faction
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

        {alliance_targets && (
          <Section title="Alliances">
            <Box bold mb={1}>
              Allies
            </Box>
            {!allies || allies.length === 0 ? (
              <Box color="label" mb={1}>
                No allied factions.
              </Box>
            ) : (
              allies.map((f) => (
                <Box key={f.uid} mb={1}>
                  {f.name}
                  {canManage && (
                    <Button
                      ml={1}
                      color="bad"
                      icon="link-slash"
                      onClick={() => act('break_alliance', { uid: f.uid })}
                    >
                      Break
                    </Button>
                  )}
                </Box>
              ))
            )}
            {!!incoming_alliance_requests && incoming_alliance_requests.length > 0 && (
              <>
                <Box bold mt={1} mb={1}>
                  Incoming Requests
                </Box>
                {incoming_alliance_requests.map((f) => (
                  <Box key={f.uid} mb={1}>
                    {f.name}
                    {canManage && (
                      <>
                        <Button
                          ml={1}
                          color="good"
                          icon="handshake"
                          onClick={() => act('accept_alliance', { uid: f.uid })}
                        >
                          Accept
                        </Button>
                        <Button
                          ml={1}
                          icon="xmark"
                          onClick={() => act('decline_alliance', { uid: f.uid })}
                        >
                          Decline
                        </Button>
                      </>
                    )}
                  </Box>
                ))}
              </>
            )}
            {!!outgoing_alliance_requests && outgoing_alliance_requests.length > 0 && (
              <>
                <Box bold mt={1} mb={1}>
                  Outgoing Requests
                </Box>
                {outgoing_alliance_requests.map((f) => (
                  <Box key={f.uid} mb={1}>
                    {f.name} -- Pending
                    {canManage && (
                      <Button
                        ml={1}
                        icon="xmark"
                        onClick={() => act('withdraw_alliance', { uid: f.uid })}
                      >
                        Withdraw
                      </Button>
                    )}
                  </Box>
                ))}
              </>
            )}
            {canManage && alliance_targets.length > 0 && (
              <Box mt={1}>
                <Box bold mb={1}>
                  Propose Alliance
                </Box>
                <Stack>
                  <Stack.Item>
                    <select
                      value={allianceTarget}
                      onChange={(e) => setAllianceTarget(e.target.value)}
                      style={{ marginRight: '4px' }}
                    >
                      <option value="">-- Select faction --</option>
                      {alliance_targets.map((f) => (
                        <option key={f.uid} value={f.uid}>
                          {f.name}
                        </option>
                      ))}
                    </select>
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      color="good"
                      disabled={!allianceTarget}
                      onClick={() => {
                        act('propose_alliance', { uid: allianceTarget });
                        setAllianceTarget('');
                      }}
                    >
                      Propose
                    </Button>
                  </Stack.Item>
                </Stack>
              </Box>
            )}
          </Section>
        )}

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
                      <Button
                        compact
                        color="bad"
                        icon="user-slash"
                        ml={1}
                        disabled={member.rank >= 2 && op_rank !== 99}
                        tooltip={
                          member.rank >= 2 && op_rank !== 99
                            ? 'This member holds command rank -- only an admin can remove them.'
                            : "Revokes this member's ID and erases their membership record entirely -- they would need to be issued a new ID to rejoin."
                        }
                        onClick={() =>
                          act('remove_member', {
                            target_ckey: member.ckey,
                          })
                        }
                      >
                        Remove
                      </Button>
                      {!!member.clocked_in && (
                        <Button
                          compact
                          color="average"
                          icon="clock"
                          ml={1}
                          tooltip="Clocks this member out -- they stop receiving payroll until they clock back in themselves."
                          onClick={() =>
                            act('force_clock_out', {
                              target_ckey: member.ckey,
                            })
                          }
                        >
                          Clock Out
                        </Button>
                      )}
                    </Table.Cell>
                  )}
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>

        {/* Shareholders Section -- only exists once listed on the exchange */}
        {!!stock_listed && (
          <Section
            title="Shareholders"
            buttons={
              <Box color="label">
                {shareholder_total_percent}% allocated
              </Box>
            }
          >
            {!shareholders || shareholders.length === 0 ? (
              <Box italic color="label">
                No shareholders yet.
              </Box>
            ) : (
              <Table>
                <Table.Row header>
                  <Table.Cell>Name</Table.Cell>
                  <Table.Cell>Percent</Table.Cell>
                </Table.Row>
                {shareholders
                  .slice()
                  .sort((a, b) => b.percent - a.percent)
                  .map((sh) => (
                    <Table.Row key={sh.char_name}>
                      <Table.Cell bold>{sh.char_name}</Table.Cell>
                      <Table.Cell>{sh.percent}%</Table.Cell>
                    </Table.Row>
                  ))}
              </Table>
            )}
          </Section>
        )}

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
