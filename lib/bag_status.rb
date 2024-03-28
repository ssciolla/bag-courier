module BagStatus
  COPIED = "copied"
  COPYING = "copying"
  BAGGED = "bagged"
  BAGGING = "bagging"
  DEPOSITING = "depositing"
  DEPOSITED = "deposited"
  DEPOSIT_SKIPPED = "deposit_skipped"
  FAILED = "failed"
  PACKED = "packed"
  PACKING = "packing"
  VALIDATED = "validated"
  VALIDATING = "validating"
  VALIDATION_SKIPPED = "validation_skipped"
  VERIFIED = "verified"
  VERIFY_FAILED = "verify_failed"

  def self.check_status?(status)
    constants.any? { |bag_status| const_get(bag_status) == status }
  end
end
