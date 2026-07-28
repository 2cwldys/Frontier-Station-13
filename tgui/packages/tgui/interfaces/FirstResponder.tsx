import {
  Box,
  Button,
  Dropdown,
  NoticeBox,
  Section,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type SectorInfo = {
  name: string;
  x: number;
  y: number;
};

type OffenseEntry = {
  index: number;
  name: string;
  age: string;
  tracked: BooleanLike;
  type: 'offense' | 'distress' | 'emergency';
  can_jump: BooleanLike;
  sector_info: SectorInfo | null;
};

type TaggedEntry = {
  ref: string;
  name: string;
  restrained: BooleanLike;
  in_range: BooleanLike;
};

type TelepadChoice = {
  ref: string;
  area_name: string;
};

type RepossessedShip = {
  shuttle_id: number;
  display_name: string;
};

type TapMode = 'tag' | 'stash' | 'repossess' | 'scuttle';

type FirstResponderData = {
  faction_uid: string | null;
  faction_name: string | null;
  is_hub: BooleanLike;
  has_telepad: BooleanLike;
  telepad_choices: TelepadChoice[];
  cooldown: number;
  can_secure: BooleanLike;
  in_highsec: BooleanLike;
  distress_cooldown: number;
  offenses: OffenseEntry[];
  tagged: TaggedEntry[];
  tap_mode: TapMode;
  can_scuttle_ships: BooleanLike;
  repossessed_ships: RepossessedShip[];
};

export const FirstResponder = (props) => {
  const { act, data } = useBackend<FirstResponderData>();
  const {
    faction_uid,
    faction_name,
    is_hub,
    has_telepad,
    telepad_choices,
    cooldown,
    can_secure,
    in_highsec,
    distress_cooldown,
    offenses,
    tagged,
    tap_mode,
    can_scuttle_ships,
    repossessed_ships,
  } = data;
  const [selectedPadRef, setSelectedPadRef] = useState<string | null>(null);
  const needsPadChoice = telepad_choices.length > 1;
  const selectedAreaName =
    telepad_choices.find((t) => t.ref === selectedPadRef)?.area_name ||
    'Select a telepad';

  return (
    <NtosWindow resizable width={560} height={520}>
      <NtosWindow.Content scrollable>
        <Section title="Civilian Distress Call">
          <NoticeBox info>
            Anyone can request Hub security from a highsec zone. Your
            location is reported to nearby hub responders. Security-level
            access is required for everything else in this program.
          </NoticeBox>
          <Button
            icon="exclamation-triangle"
            color="bad"
            disabled={!in_highsec || distress_cooldown > 0}
            tooltip={
              !in_highsec
                ? 'Hub law is only enforced in highsec zones.'
                : distress_cooldown > 0
                  ? `You've already sent a distress call recently (${distress_cooldown}s remaining).`
                  : 'Alert nearby Hub security to your location.'
            }
            onClick={() => act('distress')}
          >
            Request Hub Security
            {distress_cooldown > 0 ? ` (${distress_cooldown}s)` : ''}
          </Button>
        </Section>
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
          {!can_secure && (
            <NoticeBox>
              You lack Hub security access. Response jumps, prisoner
              transport, and tagging are unavailable to you.
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
          {needsPadChoice && (
            <Dropdown
              mb={1}
              width="100%"
              selected={selectedAreaName}
              options={telepad_choices.map((t) => t.area_name)}
              onSelected={(area_name) =>
                setSelectedPadRef(
                  telepad_choices.find((t) => t.area_name === area_name)
                    ?.ref || null,
                )
              }
            />
          )}
          <Button
            icon="reply"
            color={has_telepad ? 'good' : 'grey'}
            disabled={
              !can_secure ||
              !has_telepad ||
              cooldown > 0 ||
              (needsPadChoice && !selectedPadRef)
            }
            tooltip={
              !can_secure
                ? 'Requires Hub security access.'
                : !has_telepad
                  ? 'No security telepad found for this faction network.'
                  : needsPadChoice && !selectedPadRef
                    ? 'Select a destination telepad first.'
                    : tagged.length > 0
                      ? `Teleport back to your faction security telepad with ${tagged.length} tagged prisoner(s). Tags are cleared afterward.`
                      : 'Teleport back to your faction security telepad.'
            }
            onClick={() =>
              act('return', needsPadChoice ? { pad_ref: selectedPadRef } : {})
            }
          >
            Return to Security Telepad
            {tagged.length > 0 ? ` (+${tagged.length} tagged)` : ''}
          </Button>
        </Section>
        <Section title="Tap Mode">
          <NoticeBox info>
            Tapping a person with the device does whatever mode is selected
            below. Ship seizure taps are adjacent-range only.
          </NoticeBox>
          <Box mt={1}>
            <Button
              selected={tap_mode === 'tag'}
              disabled={!can_secure}
              onClick={() => act('set_tap_mode', { mode: 'tag' })}
            >
              Tag for Transport
            </Button>
            <Button
              selected={tap_mode === 'repossess'}
              disabled={!can_secure || !is_hub}
              tooltip={!is_hub ? 'Requires a Hub-network terminal.' : undefined}
              onClick={() => act('set_tap_mode', { mode: 'repossess' })}
            >
              Repossess Ship
            </Button>
          </Box>
        </Section>
        <Section title="Force Stash a Ship">
          <NoticeBox info>
            Console action -- picks a currently-deployed, already-repossessed
            ship from a list, no tap needed. Recalls a Hub asset that's out
            and about.
          </NoticeBox>
          <Button
            mt={1}
            icon="down-to-line"
            disabled={!can_secure || !is_hub}
            tooltip={!is_hub ? 'Requires a Hub-network terminal.' : undefined}
            onClick={() => act('force_stash_picker')}
          >
            Force Stash a Repossessed Ship
          </Button>
        </Section>
        <Section title="Repossessed Ships">
          {repossessed_ships.length === 0 && (
            <NoticeBox info>
              No ships currently repossessed by the Hub.
            </NoticeBox>
          )}
          {repossessed_ships.length > 0 && (
            <Table>
              <Table.Row header>
                <Table.Cell>Ship</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {repossessed_ships.map((ship) => (
                <Table.Row key={ship.shuttle_id} className="candystripe">
                  <Table.Cell bold>{ship.display_name}</Table.Cell>
                  <Table.Cell>
                    <Button
                      icon="reply"
                      color="good"
                      disabled={!can_secure || !is_hub}
                      tooltip="Return this ship to its original owner."
                      onClick={() =>
                        act('return_to_owner', {
                          shuttle_id: ship.shuttle_id,
                        })
                      }
                    >
                      Return to Owner
                    </Button>
                    <Button
                      icon="radiation"
                      color="bad"
                      disabled={!can_secure || !is_hub || !can_scuttle_ships}
                      tooltip={
                        can_scuttle_ships
                          ? 'Permanently destroy this ship. Cannot be undone.'
                          : 'Requires officer rank or higher in the Hub.'
                      }
                      onClick={() =>
                        act('scuttle_repossessed', {
                          shuttle_id: ship.shuttle_id,
                        })
                      }
                    >
                      Scuttle
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
        <Section title="Tagged for Transport">
          {tagged.length === 0 && (
            <NoticeBox info>
              No transport tags. With Tag for Transport mode active, tap an
              apprehended (restrained or incapacitated) person with the
              device to tag them; they teleport with you on Return.
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
                      disabled={!can_secure}
                      tooltip={
                        can_secure
                          ? 'Remove this transport tag.'
                          : 'Requires Hub security access.'
                      }
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
                <Table.Cell>Type</Table.Cell>
                <Table.Cell>Offender</Table.Cell>
                <Table.Cell>When</Table.Cell>
                <Table.Cell>Signal</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {offenses.map((offense) => (
                <Table.Row key={offense.index} className="candystripe">
                  <Table.Cell
                    bold
                    color={
                      offense.type === 'emergency'
                        ? 'good'
                        : offense.type === 'distress'
                          ? 'average'
                          : 'bad'
                    }
                  >
                    {offense.type === 'emergency'
                      ? 'EMERGENCY'
                      : offense.type === 'distress'
                        ? 'DISTRESS'
                        : 'OFFENSE'}
                  </Table.Cell>
                  <Table.Cell bold>{offense.name}</Table.Cell>
                  <Table.Cell>{offense.age}</Table.Cell>
                  <Table.Cell
                    color={offense.tracked ? 'good' : 'average'}
                  >
                    {offense.tracked ? 'live track' : 'last known'}
                  </Table.Cell>
                  <Table.Cell>
                    {offense.can_jump ? (
                      <Button
                        icon="bolt"
                        color="bad"
                        disabled={!can_secure || !is_hub || cooldown > 0}
                        tooltip={
                          !can_secure
                            ? 'Requires Hub security access.'
                            : is_hub
                              ? 'Open a bluespace portal near this offender.'
                              : 'Response jumps require a Hub-network terminal.'
                        }
                        onClick={() =>
                          act('respond', { index: offense.index })
                        }
                      >
                        Respond
                      </Button>
                    ) : offense.sector_info ? (
                      <Box color="label" inline>
                        Outside Hub jurisdiction -- {offense.sector_info.name}{' '}
                        ({offense.sector_info.x}, {offense.sector_info.y})
                      </Box>
                    ) : (
                      <Box color="label" inline>
                        Outside Hub jurisdiction -- location unknown
                      </Box>
                    )}
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
