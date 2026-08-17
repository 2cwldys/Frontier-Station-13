import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type CrewEntry = { ckey: string; char_name: string; label: string | null };

type ShipSchematicData = {
  repossessed: BooleanLike;
  valid: BooleanLike;
  display_name?: string;
  stashed?: BooleanLike;
  ready?: BooleanLike;
  title_holder_name?: string;
  reported_stolen?: BooleanLike;
  can_give_title?: BooleanLike;
  needs_rename?: BooleanLike;
  away_from_home?: BooleanLike;
  shuttle_id?: number;
  save_in_progress?: BooleanLike;
  busy?: BooleanLike;
  sub_shuttle_tags?: string[];
  can_board?: BooleanLike;
  board_cooldown?: number;
  can_disembark?: BooleanLike;
  aboard_this_ship?: BooleanLike;
  crew?: CrewEntry[];
};

export const ShipSchematic = (props) => {
  const { act, data } = useBackend<ShipSchematicData>();
  const {
    repossessed,
    valid,
    display_name,
    stashed,
    ready,
    title_holder_name,
    reported_stolen,
    can_give_title,
    needs_rename,
    away_from_home,
    save_in_progress,
    busy,
    sub_shuttle_tags = [],
    can_board,
    board_cooldown,
    can_disembark,
    aboard_this_ship,
    crew = [],
  } = data;

  return (
    <Window width={400} height={560} title="Ship Schematic">
      <Window.Content scrollable>
        {!!repossessed && (
          <Section title="Status">
            <Box color="bad" bold>
              REPOSSESSED -- this schematic has been seized and no longer
              functions.
            </Box>
          </Section>
        )}
        {!repossessed && !valid && (
          <Section title="Status">
            <Box color="bad" bold>
              This schematic is voided -- it no longer corresponds to any
              ship.
            </Box>
          </Section>
        )}
        {!repossessed && !!valid && (
          <>
            <Section title={display_name}>
              <LabeledList>
                <LabeledList.Item label="Title Belongs To">
                  {title_holder_name || 'Unknown'}
                </LabeledList.Item>
                <LabeledList.Item label="Status">
                  <Box bold color={stashed ? 'good' : 'label'}>
                    {stashed ? 'Stashed' : ready ? 'Deployed' : 'Initializing...'}
                  </Box>
                </LabeledList.Item>
              </LabeledList>
              {!!reported_stolen && (
                <Box mt={1} color="bad" bold>
                  This schematic has been reported stolen.
                </Box>
              )}
              <Button
                fluid
                mt={1}
                icon="street-view"
                disabled={!stashed || !!busy || !!save_in_progress || !!needs_rename}
                tooltip={
                  busy
                    ? 'Retrieve/stash in progress -- please wait.'
                    : save_in_progress
                      ? 'World save in progress -- please wait.'
                      : needs_rename
                        ? 'Rename this ship before it can be retrieved.'
                        : undefined
                }
                onClick={() => act('retrieve')}
              >
                Retrieve
              </Button>
              <Button
                fluid
                mt={1}
                icon="box"
                disabled={
                  !!stashed ||
                  !!busy ||
                  !!save_in_progress ||
                  !!away_from_home ||
                  !ready
                }
                tooltip={
                  busy
                    ? 'Retrieve/stash in progress -- please wait.'
                    : save_in_progress
                      ? 'World save in progress -- please wait.'
                      : !ready
                        ? 'This ship is still being retrieved -- wait until it is ready to board.'
                        : away_from_home
                          ? 'This ship is currently docked -- undock before stashing.'
                          : undefined
                }
                onClick={() => act('stash')}
              >
                Stash
              </Button>
            </Section>
            <Section title="Boarding">
              {!aboard_this_ship && (
                <Button
                  fluid
                  mt={1}
                  icon="street-view"
                  disabled={!ready || !can_board || !!save_in_progress}
                  tooltip={
                    save_in_progress
                      ? 'World save in progress -- please wait.'
                      : !ready
                        ? 'This ship is still being retrieved -- wait until it is ready to board.'
                        : undefined
                  }
                  onClick={() => act('board')}
                >
                  {!ready
                    ? 'Enter Ship'
                    : can_board
                      ? 'Enter Ship'
                      : `Enter Ship (${board_cooldown}s)`}
                </Button>
              )}
              {sub_shuttle_tags.length > 0 && (
                <Button
                  fluid
                  mt={1}
                  icon="street-view"
                  disabled={!ready || !can_board || !!save_in_progress}
                  tooltip={
                    save_in_progress
                      ? 'World save in progress -- please wait.'
                      : !ready
                        ? 'This ship is still being retrieved -- wait until it is ready to board.'
                        : undefined
                  }
                  onClick={() => act('board_subship')}
                >
                  {!ready
                    ? 'Enter Sub-Ship'
                    : can_board
                      ? 'Enter Sub-Ship'
                      : `Enter Sub-Ship (${board_cooldown}s)`}
                </Button>
              )}
              <Button
                fluid
                mt={1}
                icon="user-plus"
                disabled={!can_disembark || !!save_in_progress}
                tooltip={
                  save_in_progress
                    ? 'World save in progress -- please wait.'
                    : !can_disembark
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
                disabled={!can_disembark || !!save_in_progress}
                tooltip={
                  save_in_progress
                    ? 'World save in progress -- please wait.'
                    : undefined
                }
                onClick={() => act('disembark')}
              >
                Exit Ship
              </Button>
            </Section>
            <Section title="Identity">
              <Button fluid icon="pen" onClick={() => act('rename_ship')}>
                Rename Ship
              </Button>
              {sub_shuttle_tags.length > 0 && (
                <Button
                  fluid
                  mt={1}
                  icon="pen"
                  onClick={() => act('rename_subship')}
                >
                  Rename Sub-ship
                </Button>
              )}
              {!!can_give_title && (
                <Button
                  fluid
                  mt={1}
                  icon="right-left"
                  disabled={!!reported_stolen}
                  tooltip={
                    reported_stolen
                      ? 'This ship is reported stolen -- return it to its rightful owner first.'
                      : "Signs this ship's title over to another character. Also clears the crew roster."
                  }
                  onClick={() => act('give_title')}
                >
                  Give Title
                </Button>
              )}
            </Section>
            <Section title="Crew">
              <LabeledList>
                {crew.length === 0 && (
                  <LabeledList.Item label="Crew">No crew added.</LabeledList.Item>
                )}
                {crew.map((c) => (
                  <LabeledList.Item key={`${c.ckey}|${c.char_name}`} label={c.char_name}>
                    {c.ckey}
                    {c.label ? ` (${c.label})` : ''}
                    <Button
                      ml={1}
                      color="bad"
                      onClick={() =>
                        act('remove_crew', { ckey: c.ckey, char_name: c.char_name })
                      }
                    >
                      Remove
                    </Button>
                  </LabeledList.Item>
                ))}
              </LabeledList>
              <Button fluid mt={1} icon="user-plus" onClick={() => act('add_crew')}>
                Add Crew
              </Button>
            </Section>
            <Section title="Danger Zone">
              <Button
                fluid
                color="bad"
                disabled={!stashed || !!busy}
                tooltip={busy ? 'Retrieve/stash in progress -- please wait.' : undefined}
                onClick={() => act('sell')}
              >
                Remove
              </Button>
              <Button
                fluid
                mt={1}
                color="bad"
                icon="radiation"
                disabled={!!busy}
                tooltip={busy ? 'Retrieve/stash in progress -- please wait.' : undefined}
                onClick={() => act('scuttle')}
              >
                Scuttle
              </Button>
            </Section>
            <Box mt={1} color="label">
              Deposit this schematic into any console or laptop to bank it
              for safekeeping -- it can be withdrawn again from the Drydock
              program.
            </Box>
          </>
        )}
      </Window.Content>
    </Window>
  );
};
