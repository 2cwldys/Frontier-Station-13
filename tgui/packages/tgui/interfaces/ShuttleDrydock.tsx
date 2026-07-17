import { Box, Button, LabeledList, Section, Tabs } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type FactionBeacon = { faction_uid: string; faction_name: string };
type ShuttleRow = {
  shuttle_id: number;
  template_id: string;
  owner_ckey: string | null;
  owner_char_name: string | null;
  faction_uid: string | null;
  stashed: BooleanLike;
  custom_name: string | null;
  custom_class: string | null;
  ready: BooleanLike;
  display_name: string;
};

type CrewEntry = { ckey: string; char_name: string; label: string | null };

type Template = {
  template_id: string;
  display_name: string;
  price: number;
};

type DrydockData = {
  faction_beacon: FactionBeacon | null;
  own_faction_name: string | null;
  personal_shuttles: ShuttleRow[];
  faction_shuttles: ShuttleRow[];
  crew_by_ship: Record<string, CrewEntry[]>;
  is_admin: BooleanLike;
  can_buy_faction: BooleanLike;
  templates: Template[];
  can_board: BooleanLike;
  board_cooldown: number;
  can_disembark: BooleanLike;
};

export const ShuttleDrydock = (props) => {
  const { act, data } = useBackend<DrydockData>();
  const [tab, setTab] = useState('Drydock');
  const [buyAsFaction, setBuyAsFaction] = useState(false);

  // Personal ships retrieve into whatever sector the computer is currently
  // in -- no anchor needed. Faction ships still need their own faction's
  // beacon in range.
  const renderRow = (row: ShuttleRow) => {
    const retrieveBlocked = row.faction_uid && !data.faction_beacon;
    const notReady = !row.stashed && !row.ready;
    return (
      <LabeledList.Item key={row.shuttle_id} label={row.display_name}>
        #{row.shuttle_id}
        {row.custom_class ? ` (${row.custom_class})` : ''} --{' '}
        {row.stashed ? 'Stashed' : notReady ? 'Initializing...' : 'Deployed'}
        <Button
          ml={1}
          disabled={!row.stashed || !!retrieveBlocked}
          onClick={() => act('retrieve', { shuttle_id: row.shuttle_id })}
        >
          Retrieve
        </Button>
        <Button
          disabled={!!row.stashed || notReady}
          onClick={() => act('stash', { shuttle_id: row.shuttle_id })}
        >
          Stash
        </Button>
        <Button
          icon="pen"
          onClick={() => act('rename_ship', { shuttle_id: row.shuttle_id })}
        >
          Rename
        </Button>
        <Button
          color="bad"
          disabled={!row.stashed}
          onClick={() => act('sell', { shuttle_id: row.shuttle_id })}
        >
          Remove
        </Button>
        <Button
          color="bad"
          icon="radiation"
          onClick={() => act('scuttle', { shuttle_id: row.shuttle_id })}
        >
          Scuttle
        </Button>
      </LabeledList.Item>
    );
  };

  return (
    <NtosWindow width={480} height={420}>
      <NtosWindow.Content scrollable>
        <Tabs>
          <Tabs.Tab selected={tab === 'Drydock'} onClick={() => setTab('Drydock')}>
            Drydock
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 'Market'} onClick={() => setTab('Market')}>
            Market
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 'Crew'} onClick={() => setTab('Crew')}>
            Crew
          </Tabs.Tab>
        </Tabs>
        {tab === 'Drydock' && (
          <>
            <Section>
              <Button
                fluid
                icon="street-view"
                disabled={!data.can_board}
                onClick={() => act('board')}
              >
                {data.can_board
                  ? 'Enter Ship'
                  : `Enter Ship (${data.board_cooldown}s)`}
              </Button>
              <Button
                fluid
                icon="user-plus"
                disabled={!data.can_board}
                onClick={() => act('invite_board')}
              >
                Invite to Board
              </Button>
              <Button
                fluid
                icon="right-from-bracket"
                disabled={!data.can_disembark}
                onClick={() => act('disembark')}
              >
                Exit Ship
              </Button>
              <Box color="label" mt={1}>
                {data.faction_beacon
                  ? `Faction beacon in range: ${data.faction_beacon.faction_name}`
                  : 'No faction beacon in range -- faction ships cannot retrieve here.'}
              </Box>
            </Section>
            <Section title="Personal">
              <LabeledList>{data.personal_shuttles.map(renderRow)}</LabeledList>
            </Section>
            <Section
              title={
                data.own_faction_name
                  ? `Faction: ${data.own_faction_name}`
                  : 'Faction'
              }
            >
              <LabeledList>{data.faction_shuttles.map(renderRow)}</LabeledList>
            </Section>
          </>
        )}
        {tab === 'Market' && (
          <Section title="Drydock Market">
            {!!data.can_buy_faction && (
              <Button
                selected={buyAsFaction}
                onClick={() => setBuyAsFaction(!buyAsFaction)}
              >
                Buy as faction ship
              </Button>
            )}
            <LabeledList>
              {data.templates.map((t) => (
                <LabeledList.Item key={t.template_id} label={t.display_name}>
                  {t.price} cr
                  <Button
                    ml={1}
                    onClick={() =>
                      act('buy_template', {
                        template_id: t.template_id,
                        as_faction: buyAsFaction,
                      })
                    }
                  >
                    Buy
                  </Button>
                </LabeledList.Item>
              ))}
            </LabeledList>
          </Section>
        )}
        {tab === 'Crew' && (
          <Section title="Crew Lists">
            {[...data.personal_shuttles, ...data.faction_shuttles].map(
              (row) => {
                const crew = data.crew_by_ship[row.shuttle_id] || [];
                return (
                  <Section
                    key={row.shuttle_id}
                    title={`${row.template_id} #${row.shuttle_id}`}
                    level={2}
                  >
                    <LabeledList>
                      {crew.length === 0 && (
                        <LabeledList.Item label="Crew">
                          No crew added.
                        </LabeledList.Item>
                      )}
                      {crew.map((c) => (
                        <LabeledList.Item
                          key={`${c.ckey}|${c.char_name}`}
                          label={c.char_name}
                        >
                          {c.ckey}
                          {c.label ? ` (${c.label})` : ''}
                          <Button
                            ml={1}
                            color="bad"
                            onClick={() =>
                              act('remove_crew', {
                                shuttle_id: row.shuttle_id,
                                ckey: c.ckey,
                                char_name: c.char_name,
                              })
                            }
                          >
                            Remove
                          </Button>
                        </LabeledList.Item>
                      ))}
                    </LabeledList>
                    <Button
                      mt={1}
                      icon="user-plus"
                      onClick={() =>
                        act('add_crew', { shuttle_id: row.shuttle_id })
                      }
                    >
                      Add Crew
                    </Button>
                  </Section>
                );
              },
            )}
            {data.personal_shuttles.length === 0 &&
              data.faction_shuttles.length === 0 && (
                <Box color="label">You have no ships to manage crew for.</Box>
              )}
          </Section>
        )}
      </NtosWindow.Content>
    </NtosWindow>
  );
};
