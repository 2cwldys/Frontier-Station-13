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

type ExportEntry = {
  name: string;
  price: number;
};

type CargoExportsData = {
  faction_uid: string | null;
  faction_name: string | null;
  faction_balance: number | null;
  has_telepad: BooleanLike;
  status_message: string;
  export_catalog: ExportEntry[];
  op_rank: number; // -1 = non-member, 0+ = rank, 99 = admin
  is_personal: BooleanLike;
  personal_owner_name: string | null;
  has_personal_telepad: BooleanLike;
  personal_balance: number | null;
  operator_faction_name: string | null;
  operator_faction_balance: number | null;
  is_crew: BooleanLike;
  crew_ship_name: string | null;
  has_crew_telepad: BooleanLike;
  crew_balance: number | null;
};

export const CargoExports = (props) => {
  const { act, data } = useBackend<CargoExportsData>();
  const {
    faction_uid,
    faction_name,
    faction_balance,
    has_telepad,
    status_message,
    export_catalog,
    op_rank,
    is_personal,
    personal_owner_name,
    has_personal_telepad,
    personal_balance,
    operator_faction_name,
    operator_faction_balance,
    is_crew,
    crew_ship_name,
    has_crew_telepad,
    crew_balance,
  } = data;

  if (!faction_uid && !is_personal && !is_crew) {
    return (
      <NtosWindow width={500} height={300}>
        <NtosWindow.Content>
          <Section title="Not Linked">
            <NoticeBox>
              This console is not linked to a faction, and isn&apos;t
              personally or crew tagged either. Insert your faction ID card
              and click below to link it, or tag this console with a faction
              tagger.
            </NoticeBox>
            {data.status_message && (
              <Box bold color="bad" mt={1}>
                {data.status_message}
              </Box>
            )}
            <Button
              mt={2}
              icon="link"
              color="good"
              onClick={() => act('link_faction')}
            >
              Link This Console to My Faction
            </Button>
          </Section>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  const canExport = is_personal || is_crew || op_rank >= 1;
  const telepadReady = is_personal
    ? has_personal_telepad
    : is_crew
      ? has_crew_telepad
      : has_telepad;

  return (
    <NtosWindow resizable width={600} height={600}>
      <NtosWindow.Content scrollable>
        <Section
          title={
            is_personal
              ? `${personal_owner_name} — Personal Cargo Exports`
              : is_crew
                ? `${crew_ship_name ?? 'Ship'} — Crew Cargo Exports`
                : `${faction_name ?? faction_uid} — Cargo Exports`
          }
          buttons={
            canExport && (
              <Button
                icon="upload"
                color={telepadReady ? 'good' : 'grey'}
                disabled={!telepadReady}
                tooltip={
                  !telepadReady
                    ? is_personal
                      ? 'No personally-tagged telepad found. Place and personally tag one nearby.'
                      : is_crew
                        ? 'No crew-tagged telepad found. Place and crew-tag one nearby.'
                        : 'No faction telepad found. Place and link a cargo telepad.'
                    : 'Scan telepad and export all items.'
                }
                onClick={() => act('export_now')}
              >
                Export Items at Telepad
              </Button>
            )
          }
        >
          {is_personal ? (
            <Box mb={1}>
              Personal Balance:{' '}
              <b>
                {personal_balance != null
                  ? `${personal_balance} credits`
                  : 'N/A'}
              </b>
              {operator_faction_name && (
                <Box>
                  {operator_faction_name} Balance:{' '}
                  <b>
                    {operator_faction_balance != null
                      ? `${operator_faction_balance} credits`
                      : 'N/A'}
                  </b>
                </Box>
              )}
              <Box color="label">
                Exports are credited directly to your own personal bank
                account, not a faction.
              </Box>
            </Box>
          ) : is_crew ? (
            <Box mb={1}>
              {crew_ship_name ?? 'Ship'} Crew Balance:{' '}
              <b>{crew_balance != null ? `${crew_balance} credits` : 'N/A'}</b>
              <Box color="label">
                Exports are credited to the ship owner&apos;s account, not
                yours.
              </Box>
            </Box>
          ) : (
            <Box mb={1}>
              Faction Balance:{' '}
              <b>{faction_balance != null ? `${faction_balance} credits` : 'N/A'}</b>
            </Box>
          )}

          {status_message && (
            <Box
              bold
              mb={1}
              color={status_message.includes('Exported') ? 'good' : 'label'}
            >
              {status_message}
            </Box>
          )}

          {!telepadReady && (
            <NoticeBox color="orange">
              {is_personal
                ? 'No personally-tagged cargo telepad detected. Place a telepad and personally tag it with a faction tagger.'
                : is_crew
                  ? 'No crew-tagged cargo telepad detected. Place a telepad and crew-tag it with a faction tagger.'
                  : 'No faction cargo telepad detected. Place a telepad and swipe your faction ID on it to link it to this network.'}
            </NoticeBox>
          )}

          {!canExport && (
            <NoticeBox>Officer rank required to process exports.</NoticeBox>
          )}
        </Section>

        <Section title="Export Catalog">
          <Box color="label" mb={1}>
            Place items or crates on the faction telepad, then click &quot;Export
            Items at Telepad&quot;. Prices reflect current market rates
            (diminishing returns apply).
          </Box>
          <Table>
            <Table.Row header>
              <Table.Cell>Item Type</Table.Cell>
              <Table.Cell>Price per Unit</Table.Cell>
            </Table.Row>
            {(export_catalog ?? []).map((entry) => (
              <Table.Row key={entry.name}>
                <Table.Cell>{entry.name}</Table.Cell>
                <Table.Cell>{entry.price} cr</Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
