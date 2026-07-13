import { Button, Dropdown, LabeledList, Section, Tabs } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Beacon = { tag: string; label: string; faction_restricted: string | null };
type ShuttleRow = {
  shuttle_id: number;
  template_id: string;
  owner_ckey: string | null;
  faction_uid: string | null;
  stashed: BooleanLike;
};

type Template = {
  template_id: string;
  display_name: string;
  price: number;
};

type DrydockData = {
  beacons: Beacon[];
  selected_beacon: string | null;
  own_faction_name: string | null;
  personal_shuttles: ShuttleRow[];
  faction_shuttles: ShuttleRow[];
  is_admin: BooleanLike;
  can_buy_faction: BooleanLike;
  templates: Template[];
  can_board: BooleanLike;
  board_cooldown: number;
};

export const ShuttleDrydock = (props) => {
  const { act, data } = useBackend<DrydockData>();
  const [tab, setTab] = useState('Drydock');
  const [buyAsFaction, setBuyAsFaction] = useState(false);

  const renderRow = (row: ShuttleRow) => (
    <LabeledList.Item key={row.shuttle_id} label={row.template_id}>
      #{row.shuttle_id} -- {row.stashed ? 'Stashed' : 'Deployed'}
      <Button
        ml={1}
        disabled={!row.stashed || !data.selected_beacon}
        onClick={() => act('retrieve', { shuttle_id: row.shuttle_id })}
      >
        Retrieve
      </Button>
      <Button
        disabled={!!row.stashed}
        onClick={() => act('stash', { shuttle_id: row.shuttle_id })}
      >
        Stash
      </Button>
      <Button
        color="bad"
        disabled={!row.stashed}
        onClick={() => act('sell', { shuttle_id: row.shuttle_id })}
      >
        Remove
      </Button>
    </LabeledList.Item>
  );

  return (
    <NtosWindow width={480} height={420}>
      <NtosWindow.Content scrollable>
        <Tabs>
          <Tabs.Tab selected={tab === 'Drydock'} onClick={() => setTab('Drydock')}>
            Drydock
          </Tabs.Tab>
          <Tabs.Tab
            selected={tab === 'Beacon Status'}
            onClick={() => setTab('Beacon Status')}
          >
            Beacon Status
          </Tabs.Tab>
          <Tabs.Tab selected={tab === 'Market'} onClick={() => setTab('Market')}>
            Market
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
        {tab === 'Beacon Status' && (
          <Section title="Nearby Beacons">
            <Dropdown
              width="100%"
              selected={data.selected_beacon || 'No beacons in range'}
              options={data.beacons.map((b) => b.tag)}
              onSelected={(tag) => act('select_beacon', { tag })}
            />
            {data.beacons
              .filter((b) => b.tag === data.selected_beacon)
              .map((b) => (
                <LabeledList key={b.tag}>
                  <LabeledList.Item label="Label">{b.label}</LabeledList.Item>
                  <LabeledList.Item label="Faction">
                    {b.faction_restricted || 'Public'}
                  </LabeledList.Item>
                </LabeledList>
              ))}
          </Section>
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
      </NtosWindow.Content>
    </NtosWindow>
  );
};
