import {
  Box,
  Button,
  NoticeBox,
  Section,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type OffenseEntry = {
  index: number;
  name: string;
  age: string;
  tracked: BooleanLike;
};

type TaggedEntry = {
  ref: string;
  name: string;
  restrained: BooleanLike;
  in_range: BooleanLike;
};

type FirstResponderData = {
  faction_uid: string | null;
  faction_name: string | null;
  is_hub: BooleanLike;
  has_telepad: BooleanLike;
  cooldown: number;
  offenses: OffenseEntry[];
  tagged: TaggedEntry[];
};

export const FirstResponder = (props) => {
  const { act, data } = useBackend<FirstResponderData>();
  const {
    faction_uid,
    faction_name,
    is_hub,
    has_telepad,
    cooldown,
    offenses,
    tagged,
  } = data;

  return (
    <NtosWindow resizable width={560} height={520}>
      <NtosWindow.Content scrollable>
        <Section title="First Responder — Hub Security Rapid Response">
          {!faction_uid && (
            <NoticeBox>
              This terminal is not linked to any faction network. Link it via
              its faction shackle to use First Responder.
            </NoticeBox>
          )}
          {faction_uid && !is_hub && (
            <NoticeBox>
              This terminal is on the {faction_name ?? faction_uid} network.
              Response jumps require a Hub-network terminal; only the return
              teleport to your faction&apos;s security telepad is available.
            </NoticeBox>
          )}
          <Box mb={1}>
            Teleporter status:{' '}
            {cooldown > 0 ? (
              <Box inline bold color="bad">
                recharging ({cooldown}s)
              </Box>
            ) : (
              <Box inline bold color="good">
                ready
              </Box>
            )}
          </Box>
          <Button
            icon="reply"
            color={has_telepad ? 'good' : 'grey'}
            disabled={!has_telepad || cooldown > 0}
            tooltip={
              has_telepad
                ? tagged.length > 0
                  ? `Teleport back to your faction security telepad with ${tagged.length} tagged prisoner(s). Tags are cleared afterward.`
                  : 'Teleport back to your faction security telepad.'
                : 'No security telepad found for this faction network.'
            }
            onClick={() => act('return')}
          >
            Return to Security Telepad
            {tagged.length > 0 ? ` (+${tagged.length} tagged)` : ''}
          </Button>
        </Section>
        <Section title="Tagged for Transport">
          {tagged.length === 0 && (
            <NoticeBox info>
              No transport tags. With this program open, tap an apprehended
              (restrained or incapacitated) person with the device to tag
              them; they teleport with you on Return.
            </NoticeBox>
          )}
          {tagged.length > 0 && (
            <Table>
              <Table.Row header>
                <Table.Cell>Prisoner</Table.Cell>
                <Table.Cell>State</Table.Cell>
                <Table.Cell>Range</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {tagged.map((prisoner) => (
                <Table.Row key={prisoner.ref} className="candystripe">
                  <Table.Cell bold>{prisoner.name}</Table.Cell>
                  <Table.Cell
                    color={prisoner.restrained ? 'good' : 'average'}
                  >
                    {prisoner.restrained ? 'restrained' : 'unrestrained'}
                  </Table.Cell>
                  <Table.Cell color={prisoner.in_range ? 'good' : 'bad'}>
                    {prisoner.in_range ? 'in range' : 'OUT OF RANGE'}
                  </Table.Cell>
                  <Table.Cell>
                    <Button
                      icon="times"
                      color="average"
                      tooltip="Remove this transport tag."
                      onClick={() => act('untag', { ref: prisoner.ref })}
                    >
                      Untag
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
        <Section title="Recent Highsec Offenses">
          {offenses.length === 0 && (
            <NoticeBox info>
              No highsec offenses on record. Stay vigilant.
            </NoticeBox>
          )}
          {offenses.length > 0 && (
            <Table>
              <Table.Row header>
                <Table.Cell>Offender</Table.Cell>
                <Table.Cell>When</Table.Cell>
                <Table.Cell>Signal</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {offenses.map((offense) => (
                <Table.Row key={offense.index} className="candystripe">
                  <Table.Cell bold>{offense.name}</Table.Cell>
                  <Table.Cell>{offense.age}</Table.Cell>
                  <Table.Cell
                    color={offense.tracked ? 'good' : 'average'}
                  >
                    {offense.tracked ? 'live track' : 'last known'}
                  </Table.Cell>
                  <Table.Cell>
                    <Button
                      icon="bolt"
                      color="bad"
                      disabled={!is_hub || cooldown > 0}
                      tooltip={
                        is_hub
                          ? 'Open a bluespace portal near this offender.'
                          : 'Response jumps require a Hub-network terminal.'
                      }
                      onClick={() =>
                        act('respond', { index: offense.index })
                      }
                    >
                      Respond
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
