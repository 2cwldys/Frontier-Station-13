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
  } = data;

  if (!faction_uid) {
    return (
      <NtosWindow width={500} height={300}>
        <NtosWindow.Content>
          <Section title="Not Linked">
            <NoticeBox>
              This console is not linked to a faction. Insert your faction ID card
              and click below to link it.
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

  const canExport = op_rank >= 1;

  return (
    <NtosWindow resizable width={600} height={600}>
      <NtosWindow.Content scrollable>
        <Section
          title={`${faction_name ?? faction_uid} — Cargo Exports`}
          buttons={
            canExport && (
              <Button
                icon="upload"
                color={has_telepad ? 'good' : 'grey'}
                disabled={!has_telepad}
                tooltip={
                  !has_telepad
                    ? 'No faction telepad found. Place and link a cargo telepad.'
                    : 'Scan telepad and export all items.'
                }
                onClick={() => act('export_now')}
              >
                Export Items at Telepad
              </Button>
            )
          }
        >
          <Box mb={1}>
            Faction Balance:{' '}
            <b>{faction_balance != null ? `${faction_balance} credits` : 'N/A'}</b>
          </Box>

          {status_message && (
            <Box
              bold
              mb={1}
              color={status_message.includes('Exported') ? 'good' : 'label'}
            >
              {status_message}
            </Box>
          )}

          {!has_telepad && (
            <NoticeBox color="orange">
              No faction cargo telepad detected. Place a telepad and swipe your
              faction ID on it to link it to this network.
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
