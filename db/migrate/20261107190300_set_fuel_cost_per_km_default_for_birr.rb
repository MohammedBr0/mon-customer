# frozen_string_literal: true

# The fuel hint used euros per km (0.12). In Birr a typical car costs about 8 Br per km.
class SetFuelCostPerKmDefaultForBirr < ActiveRecord::Migration[7.1]
  def up
    change_column_default :users, :vehicle_avg_consumption, from: 0.12, to: 8.0
    execute 'UPDATE users SET vehicle_avg_consumption = 8.0 WHERE vehicle_avg_consumption = 0.12'
  end

  def down
    change_column_default :users, :vehicle_avg_consumption, from: 8.0, to: 0.12
  end
end
