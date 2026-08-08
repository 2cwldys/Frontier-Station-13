import {
  Box,
  Button,
  Divider,
  Flex,
  LabeledList,
  NoticeBox,
  Section,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

export type IDData = {
  station_name: string;
  have_id_slot: BooleanLike;
  have_printer: BooleanLike;
  authenticated: BooleanLike;
  can_print_replacement: BooleanLike;

  has_id: BooleanLike;
  id_rank: string;
  id_owner: string;
  id_name: string;

  regions: Region[];

  faction_jobs: Job[];
  faction_network: string | null;
  faction_name: string | null;
  faction_officer: BooleanLike;
  can_dispense_faction_id: BooleanLike;
  can_leave_faction: BooleanLike;
  clocked_in: BooleanLike;

  can_print_hub_laws: BooleanLike;
  hub_law_cooldown_text: string | null;
};

type Access = {
  desc: string;
  ref: string;
  allowed: BooleanLike;
};

type Region = {
  name: string;
  accesses: Access[];
};

type Job = {
  target_rank: string;
  job: string;
  rank: number;
  pay_rate: number;
};

export const IDCardModification = (props) => {
  const { act, data } = useBackend<IDData>();

  return (
    <NtosWindow resizable width={650} height={700}>
      <NtosWindow.Content scrollable>
        <Section title="Identification Input">
          {!data.has_id ? (
            <NoticeBox>Please insert an ID to continue.</NoticeBox>
          ) : (
            ''
          )}
          <LabeledList>
            <LabeledList.Item label="Target Identity">
              <Button
                content={data.has_id ? data.id_name : '------'}
                icon="credit-card"
                onClick={() => act('eject')}
              />
            </LabeledList.Item>
          </LabeledList>
          {data.has_id && data.authenticated ? <AccessModification /> : ''}
        </Section>
        <Section title="Self-Service">
          <LabeledList>
            <LabeledList.Item label="Replacement ID">
              <Button
                icon="id-card"
                content="Print Replacement ID"
                color="teal"
                tooltip="Print a new ID card for yourself based on your crew record. Any existing cards are revoked."
                onClick={() => act('print_replacement')}
              />
            </LabeledList.Item>
            {!!data.can_leave_faction && (
              <LabeledList.Item label={data.faction_name ?? 'Faction'}>
                <Button
                  icon={data.clocked_in ? 'clock' : 'right-to-bracket'}
                  content={data.clocked_in ? 'Clock Out' : 'Clock In'}
                  color={data.clocked_in ? 'bad' : 'good'}
                  tooltip={
                    data.clocked_in
                      ? "Clock out -- you'll stop receiving payroll from this faction until you clock back in."
                      : 'Clock in -- required to receive payroll from this faction. 5 minute cooldown between toggles.'
                  }
                  onClick={() => act('toggle_clock')}
                />
                <Button
                  icon="right-from-bracket"
                  content={`Leave ${data.faction_name ?? 'Faction'}`}
                  color="bad"
                  ml={1}
                  tooltip="Leave this faction -- your ID access is revoked and your membership record erased. You would need to be re-issued an ID to rejoin."
                  onClick={() => act('leave_faction')}
                />
              </LabeledList.Item>
            )}
          </LabeledList>
        </Section>
        <Section title="Hub Laws">
          <LabeledList>
            <LabeledList.Item label="Hub Law Book">
              <Button
                icon="book"
                content="Print Hub Law Book"
                color="blue"
                disabled={!data.can_print_hub_laws}
                tooltip={
                  data.can_print_hub_laws
                    ? 'Print a copy of the current Hub law book.'
                    : `Available again in ${data.hub_law_cooldown_text}.`
                }
                onClick={() => act('print_hub_laws')}
              />
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};

export const AccessModification = (props) => {
  const { act, data } = useBackend<IDData>();

  return (
    <Section title="Access Modification">
      <LabeledList>
        <LabeledList.Item label="Registered Name">
          <Button
            content={data.id_owner}
            icon="edit"
            onClick={() => act('edit', { name: 1 })}
          />
        </LabeledList.Item>
        <LabeledList.Item label="Suspend">
          <Button
            icon="gavel"
            color="red"
            onClick={() => act('suspend')}
            disabled={data.id_rank === 'Suspended'}
          />
        </LabeledList.Item>
      </LabeledList>
      <Section title="Assignments">
          <LabeledList>
            {data.faction_network && data.faction_jobs.length > 0 && (
              <LabeledList.Item
                label={data.faction_name ?? data.faction_network}
                labelColor="#4FC3F7"
              >
                {data.faction_officer ? (
                  data.faction_jobs.map((job) => (
                    <Button
                      key={job.job}
                      color="light-blue"
                      disabled={data.id_rank === job.job}
                      tooltip={`Pay: ${job.pay_rate} cr/cycle`}
                      onClick={() =>
                        act('faction_assign', { faction_job: job.job })
                      }
                    >
                      {job.job}
                    </Button>
                  ))
                ) : (
                  <NoticeBox>Officer access required to assign jobs.</NoticeBox>
                )}
              </LabeledList.Item>
            )}
            <LabeledList.Item label="Base" labelColor="white">
              <Button
                content="Captain"
                color="blue"
                disabled={data.id_rank === 'Captain'}
                onClick={() => act('assign', { assign_target: 'Captain' })}
              />
              <Button
                content="Civilian"
                color="grey"
                disabled={data.id_rank === 'Civilian'}
                onClick={() => act('assign', { assign_target: 'Civilian' })}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Custom" labelColor="white">
              <Button
                content="Custom Title..."
                color="white"
                onClick={() => act('assign', { assign_target: 'Custom' })}
              />
            </LabeledList.Item>
          </LabeledList>
      </Section>
      <Section title="Access Regions">
        <Flex wrap="wrap" justify="space-between" grow={1} align="end">
          {data.regions.map((region) => (
              <Flex.Item key={region.name}>
                <Box fontSize={1.5} bold>
                  {region.name}
                </Box>
                {region.accesses.map((access) => (
                  <Button
                    key={access.ref}
                    content={access.desc}
                    selected={access.allowed}
                    onClick={() =>
                      act('access', {
                        access_target: access.ref,
                        allowed: access.allowed,
                      })
                    }
                  />
                ))}
                <Divider />
              </Flex.Item>
            ))}
        </Flex>
      </Section>
    </Section>
  );
};
