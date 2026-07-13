import { Box, Button, LabeledList, Section, Tabs } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Corvette = {
  corvette_id: number;
  template_id: string;
  stashed: BooleanLike;
  z: number | null;
};

type Template = {
  template_id: string;
  display_name: string;
  price: number;
};

type BoardingPad = {
  location: string;
};

type FactionShipsData = {
  own_faction_name: string | null;
  can_manage: BooleanLike;
  corvettes: Corvette[];
  templates: Template[];
  boarding_pads: BoardingPad[];
  can_board: BooleanLike;
  board_cooldown: number;
};

export const FactionShips = (props) => {
  const { act, data } = useBackend<FactionShipsData>();
  const [tab, setTab] = useState('Status');

  return (
    <NtosWindow width={460} height={400}>
      <NtosWindow.Content scrollable>
        {!data.own_faction_name && (
          <Section title="Faction Ship Command">
            <Box color="bad">
              You need a faction-issued ID with a real job assignment to use
              this.
            </Box>
          </Section>
        )}
        {!!data.own_faction_name && (
          <>
            <Tabs>
              <Tabs.Tab
                selected={tab === 'Status'}
                onClick={() => setTab('Status')}
              >
                Status
              </Tabs.Tab>
              <Tabs.Tab
                selected={tab === 'Market'}
                onClick={() => setTab('Market')}
              >
                Market
              </Tabs.Tab>
              <Tabs.Tab
                selected={tab === 'Boarding'}
                onClick={() => setTab('Boarding')}
              >
                Boarding
              </Tabs.Tab>
            </Tabs>
            {tab === 'Status' && (
              <Section title={`Faction: ${data.own_faction_name}`}>
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
                <LabeledList>
                  {data.corvettes.map((c) => (
                    <LabeledList.Item
                      key={c.corvette_id}
                      label={c.template_id}
                    >
                      {c.stashed ? 'Stashed' : `Deployed (z${c.z})`}
                      <Button
                        ml={1}
                        disabled={!data.can_manage || !c.stashed}
                        onClick={() =>
                          act('retrieve', { corvette_id: c.corvette_id })
                        }
                      >
                        Retrieve
                      </Button>
                      <Button
                        disabled={!data.can_manage || !!c.stashed}
                        onClick={() =>
                          act('stash', { corvette_id: c.corvette_id })
                        }
                      >
                        Stash
                      </Button>
                    </LabeledList.Item>
                  ))}
                </LabeledList>
              </Section>
            )}
            {tab === 'Market' && (
              <Section title="Corvette Market">
                <LabeledList>
                  {data.templates.map((t) => (
                    <LabeledList.Item
                      key={t.template_id}
                      label={t.display_name}
                    >
                      {t.price} cr
                      <Button
                        ml={1}
                        disabled={!data.can_manage}
                        onClick={() =>
                          act('buy', { template_id: t.template_id })
                        }
                      >
                        Buy
                      </Button>
                    </LabeledList.Item>
                  ))}
                </LabeledList>
              </Section>
            )}
            {tab === 'Boarding' && (
              <Section title="Networked Boarding Pads">
                <LabeledList>
                  {data.boarding_pads.map((p, i) => (
                    <LabeledList.Item key={i} label={`Pad ${i + 1}`}>
                      {p.location}
                    </LabeledList.Item>
                  ))}
                </LabeledList>
              </Section>
            )}
          </>
        )}
      </NtosWindow.Content>
    </NtosWindow>
  );
};
