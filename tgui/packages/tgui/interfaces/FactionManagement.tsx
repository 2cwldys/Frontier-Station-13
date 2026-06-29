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

type FactionData = {
  faction_uid: string | null;
  faction_name: string | null;
  faction_registered: BooleanLike;
  op_rank: number; // -2 = not linked, -1 = non-member, 0+ = rank, 99 = admin
  balance: number | null;
  last_payroll: number;
  jobs: FactionJob[];
  known_factions: KnownFaction[];
  transactions: FactionTransaction[];
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
    jobs,
    known_factions,
  } = data;

  if (!faction_uid) {
    return (
      <NtosWindow width={500} height={300}>
        <NtosWindow.Content>
          <NoticeBox>
            This console is not linked to a faction. Use &quot;Link to
            Faction&quot; on the computer to claim it.
          </NoticeBox>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  // Faction UID set but not yet registered in DB — offer creation to command rank
  if (!faction_registered) {
    return (
      <NtosWindow width={500} height={350}>
        <NtosWindow.Content>
          <Section title={`${faction_uid} — Unregistered`}>
            <NoticeBox>
              The network &quot;{faction_uid}&quot; has not been registered as a
              faction yet.
            </NoticeBox>
            {op_rank >= 2 && (
              <Box mt={1}>
                <Button
                  icon="plus"
                  color="good"
                  onClick={() => act('create_faction')}
                >
                  Create Faction &quot;{faction_uid}&quot;
                </Button>
              </Box>
            )}
            {op_rank < 2 && op_rank >= -1 && (
              <Box italic color="label" mt={1}>
                Contact a command-rank member to register this faction.
              </Box>
            )}
          </Section>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  if (op_rank < 1) {
    return (
      <NtosWindow width={500} height={300}>
        <NtosWindow.Content>
          <Section title={faction_name ?? faction_uid}>
            <NoticeBox>
              You are not a member of {faction_name ?? faction_uid} or do not
              have officer access.
            </NoticeBox>
          </Section>
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
      </NtosWindow.Content>
    </NtosWindow>
  );
};
