import { Box, Button, LabeledList, Section } from 'tgui-core/components';
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
};

export const ShuttleDrydock = (props) => {
  const { act, data } = useBackend<DrydockData>();
  const [buyAsFaction, setBuyAsFaction] = useState(false);

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
    <NtosWindow width={420} height={400}>
      <NtosWindow.Content scrollable>
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
        <Section title="Recoverable Schematics">
          <Box color="label" mb={1}>
            Ships whose schematic is currently in safekeeping -- deposited
            voluntarily, or banked after a Hub repossession was returned to
            its owner. Withdraw it back into your own hands, or formally give
            its title to someone else (e.g. completing a legitimate sale --
            the recipient won't be mistaken for a thief).
          </Box>
          <LabeledList>
            {data.withdrawable.length ? (
              data.withdrawable.map((row) => (
                <LabeledList.Item key={row.shuttle_id} label={row.display_name}>
                  <Button
                    icon="file-import"
                    onClick={() =>
                      act('withdraw_schematic', { shuttle_id: row.shuttle_id })
                    }
                  >
                    Withdraw Schematic
                  </Button>
                  <Button
                    ml={1}
                    icon="right-left"
                    disabled={!!row.reported_stolen}
                    tooltip={
                      row.reported_stolen
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
      </NtosWindow.Content>
    </NtosWindow>
  );
};
