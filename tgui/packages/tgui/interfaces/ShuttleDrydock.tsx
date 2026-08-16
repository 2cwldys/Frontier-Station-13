import { Box, Button, LabeledList, Section, Tabs } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Withdrawable = {
  shuttle_id: number;
  display_name: string;
  reported_stolen: BooleanLike;
};

type Template = {
  template_id: string;
  display_name: string;
  price: number;
};

type DrydockData = {
  own_faction_name: string | null;
  personal_balance: number | null;
  faction_balance: number | null;
  is_admin: BooleanLike;
  can_buy_faction: BooleanLike;
  templates: Template[];
  withdrawable: Withdrawable[];
  can_board: BooleanLike;
  board_cooldown: number;
  can_disembark: BooleanLike;
  ship_retrieving: BooleanLike;
  save_in_progress: BooleanLike;
};

export const ShuttleDrydock = (props) => {
  const { act, data } = useBackend<DrydockData>();
  const [buyAsFaction, setBuyAsFaction] = useState(false);
  const [tab, setTab] = useState<'market' | 'boarding'>('market');

  const renderTemplate = (t: Template) => (
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
  );

  return (
    <NtosWindow width={420} height={420}>
      <NtosWindow.Content scrollable>
        <Tabs>
          <Tabs.Tab selected={tab === 'market'} onClick={() => setTab('market')}>
            Market
          </Tabs.Tab>
          <Tabs.Tab
            selected={tab === 'boarding'}
            onClick={() => setTab('boarding')}
          >
            Boarding &amp; Schematics
          </Tabs.Tab>
        </Tabs>
        {tab === 'market' && (
          <Section title="Drydock Market">
            <Box mb={1} bold>
              Personal Balance:{' '}
              <Box as="span" color={data.personal_balance !== null ? 'good' : 'label'}>
                {data.personal_balance !== null ? `${data.personal_balance} credits` : 'N/A'}
              </Box>
              {data.own_faction_name && (
                <>
                  {' | '}
                  {data.own_faction_name} Balance:{' '}
                  <Box as="span" color={data.faction_balance !== null ? 'good' : 'label'}>
                    {data.faction_balance !== null ? `${data.faction_balance} credits` : 'N/A'}
                  </Box>
                </>
              )}
            </Box>
            {!!data.can_buy_faction && (
              <Button
                selected={buyAsFaction}
                onClick={() => setBuyAsFaction(!buyAsFaction)}
              >
                Buy as faction ship
              </Button>
            )}
            <LabeledList>
              {data.templates.length ? (
                data.templates.map(renderTemplate)
              ) : (
                <LabeledList.Item label="">None available.</LabeledList.Item>
              )}
            </LabeledList>
          </Section>
        )}
        {tab === 'boarding' && (
          <>
            <Section title="Boarding">
              <Box color="label" mb={1}>
                For crew granted access without a schematic in hand (see the
                schematic's own "Add Crew"). Works the same as boarding from
                the schematic itself.
              </Box>
              {!data.can_disembark && (
                <Button
                  fluid
                  icon="street-view"
                  disabled={
                    data.ship_retrieving ||
                    !data.can_board ||
                    !!data.save_in_progress
                  }
                  tooltip={
                    data.save_in_progress
                      ? 'World save in progress -- please wait.'
                      : data.ship_retrieving
                        ? 'That ship is still being retrieved -- wait until it is ready to board.'
                        : undefined
                  }
                  onClick={() => act('board')}
                >
                  {data.ship_retrieving
                    ? 'Enter Ship'
                    : data.can_board
                      ? 'Enter Ship'
                      : `Enter Ship (${data.board_cooldown}s)`}
                </Button>
              )}
              <Button
                fluid
                mt={1}
                icon="user-plus"
                disabled={!data.can_disembark || !!data.save_in_progress}
                tooltip={
                  data.save_in_progress
                    ? 'World save in progress -- please wait.'
                    : !data.can_disembark
                      ? 'You are not on board a drydock ship.'
                      : undefined
                }
                onClick={() => act('invite_board')}
              >
                Invite to Board
              </Button>
              <Button
                fluid
                mt={1}
                icon="right-from-bracket"
                disabled={!data.can_disembark || !!data.save_in_progress}
                tooltip={
                  data.save_in_progress
                    ? 'World save in progress -- please wait.'
                    : undefined
                }
                onClick={() => act('disembark')}
              >
                Exit Ship
              </Button>
            </Section>
            <Section title="Recoverable Schematics">
              <Box color="label" mb={1}>
                Ships whose schematic is currently in safekeeping -- deposited
                voluntarily, or banked after a Hub repossession was returned
                to its owner. Withdraw it back into your own hands, or
                formally give its title to someone else (e.g. completing a
                legitimate sale -- the recipient won't be mistaken for a
                thief).
              </Box>
              <LabeledList>
                {data.withdrawable.length ? (
                  data.withdrawable.map((row) => (
                    <LabeledList.Item key={row.shuttle_id} label={row.display_name}>
                      <Button
                        icon="file-import"
                        disabled={!!data.save_in_progress}
                        tooltip={
                          data.save_in_progress
                            ? 'World save in progress -- please wait.'
                            : undefined
                        }
                        onClick={() =>
                          act('withdraw_schematic', { shuttle_id: row.shuttle_id })
                        }
                      >
                        Withdraw Schematic
                      </Button>
                      <Button
                        ml={1}
                        icon="right-left"
                        disabled={!!row.reported_stolen || !!data.save_in_progress}
                        tooltip={
                          data.save_in_progress
                            ? 'World save in progress -- please wait.'
                            : row.reported_stolen
                              ? 'This ship is reported stolen -- return it to its rightful owner first.'
                              : undefined
                        }
                        onClick={() =>
                          act('give_schematic', { shuttle_id: row.shuttle_id })
                        }
                      >
                        Give Title
                      </Button>
                    </LabeledList.Item>
                  ))
                ) : (
                  <LabeledList.Item label="">None.</LabeledList.Item>
                )}
              </LabeledList>
            </Section>
          </>
        )}
      </NtosWindow.Content>
    </NtosWindow>
  );
};
